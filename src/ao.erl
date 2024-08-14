-module(ao).
-export([config/0, get/1, c/1]).

config() ->
    #{
        http_port => 8734,
        http_host => "localhost",
        arweave_gateway => "https://arweave.net",
        arweave_bundler => "https://up.arweave.net",
        su => "http://localhost:8734/su",
        mu => "http://localhost:8734/mu",
        cu => "https://cu24.ao-testnet.xyz",
        key_location => "hyperbeam-key.json",
        default_page_limit => 5
    }.

get(Key) ->
    maps:get(Key, config()).

c(X) ->
    io:format("===== DEBUG PRINT =====~n~80p~n~n", [X]),
    X.