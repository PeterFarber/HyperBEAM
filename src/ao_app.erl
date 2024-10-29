%%%-------------------------------------------------------------------
%% @doc supersu public API
%% @end
%%%-------------------------------------------------------------------

-module(ao_app).

-behaviour(application).

-export([start/2, stop/1]).
-export([attest_key/0]).

-include("include/ao.hrl").

start(_StartType, _StartArgs) ->
    ao_sup:start_link(),
    su_data:init(),
    Reg = su_registry:start(),
    _TS = su_timestamp:start(),
    _HTTP = ao_http_router:start([su_http, mu_http, cu_http]),
    {ok, Reg}.

stop(_State) ->
    ok.

pad_to_64(Addr) ->
    % Encode Addr as a hex string and convert to list for length calculation
    HexAddr = binary_to_list(binary:encode_hex(Addr)),
    % Calculate padding if necessary and pad with leading zeros
    Padding = 64 - length(HexAddr),
    lists:duplicate(Padding, $0) ++ HexAddr.

attest_key() ->
    W = ao:wallet(),
    Addr = ar_wallet:to_address(W),
    PaddedAddr = pad_to_64(Addr),
    Cmd = lists:flatten(io_lib:format("sudo gotpm attest --key AK --nonce ~s", [PaddedAddr])),
    CommandResult = os:cmd(Cmd),
    case is_list(CommandResult) of
        true ->
            % If CommandResult is a list of integers, convert it to binary
            BinaryResult = list_to_binary(CommandResult),
            Signed = ar_bundles:sign_item(
                #tx{
                    tags = [
                        {<<"Type">>, <<"TEE-Attestation">>},
                        {<<"Address">>, ar_util:id(Addr)}
                    ],
                    data = BinaryResult
                },
                W
            ),
            ao_client:upload(Signed),
            ok;
        false ->
            {error, "Unexpected output format from gotpm attest command"}
    end.

%% internal functions
