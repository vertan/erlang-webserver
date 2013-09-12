%%%        File : webserver.erl
%%%      Author : Filip Hedman <hedman.filip@gmail.com>
%%% Description : A basic thread-based web server
%%%     Created : 12 Sep 2013
%%%     Version : 0.01

-module(webserver).
-export([start/0,new_socket/1,accept_conn/1,msg_handler/1,request_handler/2,
	 create_response/2,get_file/1,get_content_type/1,parse/1,parse_header/1,packet_parser/1]).
-vsn(0.01).

-define(PORT, 8095). %% Port to use for server
-define(CONN_TYPE, "Keep-Alive"). %% Connection type in response
-define(CHARSET, "UTF-8"). %% Charset in response
-define(SERVER, "ErlangWebServer"). %% Server name in response

%%---------------------------------------------
%% Function: init/0
%% Purpose: Initializes a new web server
%%---------------------------------------------
start() ->
    io:format("Initializing server...~n"),
    new_socket(?PORT).

%%---------------------------------------------
%% Function: new_socket/1
%% Purpose: Opens a new socket on given port.
%%---------------------------------------------
new_socket(Port) ->
    io:format("Listening on port: " ++ integer_to_list(Port) ++ "~n"),
    {ok, Socket} = gen_tcp:listen(Port, [binary, {active, once}]),
    spawn(webserver, accept_conn, [Socket]).

%%---------------------------------------------
%% Function: accept_conn/1
%% Purpose: Opens an accepting socket
%%---------------------------------------------
accept_conn(Socket) ->
    {ok, Open_sock} = gen_tcp:accept(Socket),
    io:format("Accepting new requests...~n"),
    msg_handler(Open_sock),
    accept_conn(Socket).

%%---------------------------------------------
%% Function: msg_handler/1
%% Purpose: Checks for tcp requests on socket
%%---------------------------------------------
msg_handler(Open_sock) ->
    receive
	{tcp, Open_sock, Request} ->
	    io:format("Client connected...~n"),
	    Request_list = parse(Request),
	    spawn(webserver, request_handler, [Open_sock, Request_list])
    end.

%%---------------------------------------------
%% Function: request_handler/2
%% Purpose: Handles the request type
%%---------------------------------------------
request_handler(Socket, Request_list) ->
    case Request_list of
	[{get, HttpUri}|Rest] ->
	    {abs_path, Abs_path} = HttpUri,
	    File = get_file(Abs_path),
	    case File of
		{{ok, Content}, Type} ->
		    io:format("File found and loaded.~n"),
		    gen_tcp:send(Socket, create_response(200, Type)),
		    gen_tcp:send(Socket, Content);
		{{error, _}, Type} ->
		    io:format("ERROR: File not found or not working.~n"),
		    gen_tcp:send(Socket, create_response(404, Type))
	    end;
	[{_, _}|Rest] ->
	    io:format("Unknown HTTP request method!~n"),
	    gen_tcp:send(Socket, create_response(404, get_content_type("html")))
    end,
    gen_tcp:close(Socket).

%%---------------------------------------------
%% Function: create_response/2
%% Purpose: Returns the http response
%%---------------------------------------------
create_response(Code, Type) ->
    case Code of
	200 ->
	    "HTTP/1.1 200 OK\r\nServer: " ++ ?SERVER ++ "\r\nConnection: " ++ ?CONN_TYPE ++ "\r\n" ++ Type ++ "charset: " ++ ?CHARSET ++ "\r\n\r\n";
	404 ->
	    "HTTP/1.1 404 Not Found\r\nServer: " ++ ?SERVER ++ "\r\nConnection: " ++ ?CONN_TYPE ++ "\r\n" ++ Type ++ "charset: " ++ ?CHARSET ++ "\r\n\r\n"
    end.

%%---------------------------------------------
%% Function: get_file/2
%% Purpose: Returns requested file and content type
%%---------------------------------------------
get_file(Uri) ->
    io:format("Trying to read file: " ++ Uri ++ "~n"),
    [$/|File] = Uri,
    case string:tokens(Uri, ".") of
	[Filename, Ext] ->
	    Type = get_content_type(Ext),
	    {file:read_file(File), Type};
	[Other] ->
	    case string:substr(Other, string:len(Other), 1) of
		"/" ->
		    get_file(Other ++ "index.html");
		Str ->
		    get_file(Other ++ "/")			   
	    end
    end.
	
%%---------------------------------------------
%% Function: get_content_type/1
%% Purpose: Returns content type for given file extension
%%---------------------------------------------
get_content_type(Ext) ->
    case Ext of
	"html" ->
	    "Content-Type: text/html\r\n";
	"css" ->
	    "Content-Type: text/css\r\n";
	"ico" ->
	    "Content-Type: image/ico\r\n";
	"png" ->
	    timer:sleep(120000),
	    "Content-Type: image/png\r\n";
	"gif" ->
	    "Content-Type: image/gif\r\n";
	"mp3" ->
	    "Content-Type: audio/mpeg\r\n"
    end.

%%---------------------------------------------
%% Function: parse/1
%% Purpose: Parses http headers and puts it into a list
%%---------------------------------------------
parse(Raw_request) ->
    {ok, Request_type, Rest} = erlang:decode_packet(http, Raw_request, []),
    Headers = erlang:decode_packet(httph, Rest, []),
    Header_list = parse_header(Headers),
    [packet_parser(Request_type)] ++ Header_list.

%%---------------------------------------------
%% Function: parse_header/1
%% Purpose: Help function to parse/1 which parses the rest of the headers
%%---------------------------------------------
parse_header(Header) ->
    {ok, Packet, Rest} = Header,
    case packet_parser(Packet) of
	{HttpField, Value} ->
	    Next = erlang:decode_packet(httph, Rest, []),
	    [{HttpField, Value}|parse_header(Next)];
	empty_header ->
	    io:format("Header parsing complete.~n"),
	    end_of_headers
    end.
    
%%---------------------------------------------
%% Function: packet_parser/1
%% Purpose: Returns tuple with http header packet
%%---------------------------------------------
packet_parser(Packet) ->
    case Packet of
	{http_request, HttpMethod, HttpUri, HttpVersion} ->
	    case HttpMethod of
		'GET' ->
		    {get, HttpUri};
		Other_method ->
		    io:format("HttpMethod: ~p~n",[Other_method])
	    end;
	{http_header, Number, HttpField, Reserved, Value} ->
	    io:format("Header field: ~p~n", [HttpField]),
	    {HttpField, Value};
	http_eoh ->
	    io:format("No more headers!~n"),
	    empty_header;
	Wrong_format ->
	    io:format("Wrong packet format: ~p~n", [Wrong_format])
    end.
