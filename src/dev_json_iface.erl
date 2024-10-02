-module(dev_json_iface).
-export([init/1, execute/2, uses/0, stdlib/6]).

-include("include/ao.hrl").

uses() -> all.

init(S) ->
    {ok, S#{ stdlib => fun stdlib/6, json_iface => #{} }}.

execute(M, S = #{ pass := 1, json_iface := IfaceS }) ->
    {ok, S#{
        call => prep_call(M, S),
        json_iface => IfaceS#{ stdout => [] } }
    };
execute(_M, S = #{ pass := 2 }) ->
    {ok, result(S) }.

prep_call(M, #{ wasm := Port, process := Process }) ->
    {_, Module} = lists:keyfind(<<"Module">>, 1, Process#tx.tags),
    % TODO: Get block height from the assignment message
    BlockHeight = <<"0">>,
    RawMsgJson = ao_message:to_json(M),
    {Props} = jiffy:decode(RawMsgJson),
    MsgJson = jiffy:encode({Props ++ [{<<"Module">>, Module}, {<<"Block-Height">>, BlockHeight}]}),
    {ok, MsgJsonPtr} = cu_beamr_io:write_string(Port, MsgJson),
    EnvJson = jiffy:encode({[{<<"Process">>, ar_bundles:item_to_json_struct(Process)}]}),
    {ok, EnvJsonPtr} = cu_beamr_io:write_string(Port, EnvJson),
    {"handle", [MsgJsonPtr, EnvJsonPtr]}.

result(S = #{ wasm := Port, result := Res, json_iface := #{ stdout := Stdout } }) ->
    case Res of
        {error, Res} ->
            S#{
                outbox := [],
                result := #tx { tags = [{<<"Result">>, <<"Error">>}], data = Res }
            };
        {ok, [Ptr]} ->
            {ok, Str} = cu_beamr_io:read_string(Port, Ptr),
            try jiffy:decode(Str, [return_maps]) of
                % TODO: Handle all JSON interface outputs
                #{<<"ok">> := true, <<"response">> := Resp} ->
                    #{<<"Output">> := #{ <<"data">> := Data }, <<"Messages">> := Messages } = Resp,
                    S#{
                        result => 
                            #tx {
                                data = #{
                                    <<"/outbox/messages">> => [ ao_message:to_binary(ao_message:from_json(Msg)) || Msg <- Messages ],
                                    <<"/data">> => Data,
                                    <<"/stdout">> => iolist_to_binary(Stdout)
                                }
                            }
                    };
                #{<<"ok">> := false} ->
                    S#{
                        outbox => [],
                        result =>
                            #tx {
                                tags = [{<<"Result">>, <<"Error">>}],
                                data = jiffy:encode(#{
                                    <<"Error">> => <<"JSON Parse Error">>,
                                    <<"stdout">> => iolist_to_binary(Stdout),
                                    <<"Data">> => Str
                                })
                            }
                    }
            catch
                _:_ ->
                    S#{
                        outbox => [],
                        result =>
                            #tx {
                                tags = [{<<"Result">>, <<"Error">>}],
                                data = jiffy:encode(#{
                                    <<"Error">> => <<"JSON Parse Error">>,
                                    <<"stdout">> => iolist_to_binary(Stdout),
                                    <<"Data">> => Str
                                })
                            }
                    }
            end
    end.

stdlib(S = #{ json_iface := IfaceS }, Port, ModName, FuncName, Args, Sig) ->
    {IfaceS2, Res} = lib(IfaceS, Port, ModName, FuncName, Args, Sig),
    {S#{ json_iface := IfaceS2 }, Res}.

lib(S = #{ stdout := Stdout }, Port, "wasi_snapshot_preview1","fd_write", [_Fd, Ptr, Vecs, RetPtr], _Signature) ->
    %ao:c({fd_write, Fd, Ptr, Vecs, RetPtr}),
    {ok, VecData} = cu_beamr_io:read_iovecs(Port, Ptr, Vecs),
    BytesWritten = byte_size(VecData),
    %ao:c({fd_write_data, VecData}),
    NewStdio =
        case Stdout of
            undefined ->
                [VecData];
            Existing ->
                Existing ++ [VecData]
        end,
    % Set return pointer to number of bytes written
    cu_beamr_io:write(Port, RetPtr, <<BytesWritten:64/little-unsigned-integer>>),
    {S#{ stdout := NewStdio }, [0]};
lib(S, _Port, _Module, "clock_time_get", _Args, _Signature) ->
    ao:c({called, wasi_clock_time_get, 1}),
    {S, [1]};
lib(S, _Port, Module, Func, _Args, _Signature) ->
    ao:c({unimplemented_stub_called, Module, Func}),
    {S, [0]}.