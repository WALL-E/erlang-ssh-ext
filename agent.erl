%%Parallel Agent
%%
%%Todo:
%%	1:Refactoring Case sentence
%%
%%update[2012-02-27]
%%

-module(agent).
-export([do_cmd/2, hosts_cmd/2, exec/1, screen/2, cache_data/2, debug_parallel_status/1]).
-author(zhangz).
-define(TIMEOUT, infinity).
-define(RED, "\033[0;32;31m").
-define(WHITE, "\033[1;0m").

%sleep(Time) ->
%	receive
%	after Time ->
%		true
%	end.

debug_parallel_status([])->
	io:format("~s", [?RED]),
	io:format("*************************************************************~n"),
	io:format("* Timeout Hosts:[~p]~n", [get("error_hosts")]),
	io:format("*************************************************************~n"),
	io:format("~s", [?WHITE]),
	ok;
debug_parallel_status([Host|Tail])->
	case get(Host) of
        undefined ->
			case get("error_hosts") of
				undefined ->
					put("error_hosts", Host);
				Error_Hosts_count ->
					%%New_Error_Hosts_count = [Error_Hosts_count|Host],
					%%New_Error_Hosts_count = string:concat(Error_Hosts_count, Host),
					New_Error_Hosts_count = Error_Hosts_count ++ "," ++ Host,
					put("error_hosts", New_Error_Hosts_count)
			end;
        _ ->
			ok
    end,
	debug_parallel_status(Tail).
	
cache_data(Host, {error, Msg})->
	case get(Host) of
        undefined ->
            put(Host, Msg);
        Old_msg ->
            New_msg = string:concat(Old_msg, Msg),
            put(Host, New_msg)
    end;
cache_data(Host, Data)->
	if
		is_binary(Data) ->
			Msg = binary_to_list(Data);
		is_list(Data) ->
			Msg = Data
	end,
	case get(Host) of
		undefined ->
			put(Host, Msg);
		Old_msg ->
			New_msg = string:concat(Old_msg, Msg),
			put(Host, New_msg)
	end.

list_length([]) -> 
	0;    
list_length([_First|Rest]) -> 
	1 + list_length(Rest). 

do_cmd(Host, Cmd) ->
	crypto:start(),
	ssh:start(),

	%%connect
	case ssh:connect(Host,22,[{user, "root"},{silently_accept_hosts,true},{user_interaction,false}],?TIMEOUT) of
		{ok, SSH} ->
			%%channel
			case ssh_connection:session_channel(SSH, ?TIMEOUT) of
				{ok, Sid} ->
					%%execute cmd
					ssh_connection:exec(SSH, Sid, Cmd, ?TIMEOUT),
					recv(Host, SSH, Sid);
				{error, Reason} ->
					screen_server ! {error, {Host, {error, Reason}}},
					exit("timeout")
			end;
		{error, Reason} ->
			screen_server ! {error, {Host, {error, Reason}}},
			exit("timeout")
	end.

recv(Host, SSH, Sid) ->
	receive
		{ssh_cm, SSH, {data, Sid, 0,Data}} ->
			screen_server ! {data, {Host, Data}},
			recv(Host, SSH, Sid);
		{ssh_cm, SSH, {eof, Sid}} ->
			screen_server ! {eof, {Host, ok}},
			recv(Host, SSH, Sid);
		{ssh_cm, SSH, {exit_status, Sid, ExitStatus}} ->
			screen_server ! {exitstatus, {Host, ExitStatus}},
			recv(Host, SSH, Sid);
		{ssh_cm, SSH, {closed, Sid}} ->
			ok;
		{ssh_cm, SSH, {exit_signal, Sid, ExitSignal, ErrorMsg, LanguageString}} ->
			screen_server ! {exitsignal, {Host, {ExitSignal, ErrorMsg, LanguageString}}},
			recv(Host, SSH, Sid)
	end.

hosts_cmd([Host|Other_host], Cmd)->
	%%do_cmd(Host, Cmd),
	spawn(fun() -> do_cmd(Host, Cmd) end),
	hosts_cmd(Other_host, Cmd);
hosts_cmd([], _Cmd)->
	ok.

screen(Count, Hosts_count) ->
	%% Hosts_list must equal Hosts @ function exec
	Hosts_list = ["127.0.0.1", "127.0.0.1", "127.0.0.1"],
	receive
		{data, {Src, Data}} ->
			cache_data(Src, Data),
			screen(Count, Hosts_count);
		{exitstatus, {Src, Data}} ->
			if
				Data /= 0 ->
					cache_data(Src, list_to_binary("shell command error,exit code[XX]"));
            	Data == 0 ->
                    ok
			end,
			%%Output
			screen(Count, Hosts_count);
		{eof, {Src, _Data}} ->
			%%Output
			NewCount = Count + 1,
			io:format("[~2s][~3s]~n~s~n", [integer_to_list(NewCount), Src, get(Src)]),
			if 
				NewCount == Hosts_count ->
					init:stop();
				NewCount /= Hosts_count ->
					ok
			end,
			%%debug message
			if
				Count == 28 ->
					debug_parallel_status(Hosts_list);
				true ->
					ok
			end,
			screen(NewCount, Hosts_count);
		{exit_status, {_Src, _Data}} ->
			screen(Count, Hosts_count);
		{exitsignal, {_Src, _Data}} ->
			screen(Count, Hosts_count);
		{stop} ->
			%%io:format("screen server close~n"),
			ok;
		{error, {Src, Data}} ->
			cache_data(Src, Data),
			screen(Count, Hosts_count)
	end.

exec([Cmd])->
	case whereis(screen_server) of
		undefined ->
			true;
		_ ->
			screen_server ! {stop},
			try unregister(screen_server)
			catch
				error:badarg ->
					ignore
			end
	end,

	Hosts = ["127.0.0.1", "127.0.0.1", "127.0.0.1"],
	Hosts_count = list_length(Hosts),
	Pid = spawn(fun() -> screen(0, Hosts_count) end),
	register(screen_server, Pid),

	hosts_cmd(Hosts, atom_to_list(Cmd)).
