using Sockets

function urldecode(s)
    s = replace(s, "+" => " ")
    parts = split(s, "%")
    if (length(parts) == 1)
        return s
    end
    result = parts[1]
    for i=2:length(parts)
        if (parts[i] == "")
            result = result*"%"
        else 
            code = parts[i][1:2]
            result = result*(Char(parse(UInt32, code, base=16)))*parts[i][3:end]
        end
    end
    return result
end

function parse_query_string(query)
    result = Dict{String, String}()
    for parameter in split(query, "&")
        (key, value) = split(parameter, "=")
        key = urldecode(key)
        value = urldecode(value)
        result[key] = value
    end
    return result
end

mutable struct Request
    method::String
    uri::String
    protocol::String
    path::String
    args::Array{String,1}
    headers::Dict{String, String}
    form::Dict{String, String}
    body::String
    raw_data::Vector{UInt8}
    query::Dict{String, String}
    
    
    function Request(method::String, uri::String, protocol::String)
        form = Dict{String, String}()
        raw_data = []
        headers = Dict{String, String}()
        query_string_start = findfirst("?", uri)
        if (query_string_start == nothing)
            path = uri
            query = Dict{String, String}()
        else
            start = query_string_start[1]
            if (start == length(uri))
                path = (uri[1:start-1])
                query = Dict{String, String}()
            else
                path = (uri[1:start-1])
                query = parse_query_string(uri[start+1:end])
            end
        end
        new(method, uri, protocol, path, [], headers, form, "", raw_data, query)

    end
end

abstract type HTTPResponse end

struct HTMLResponse <: HTTPResponse
    status::Int
    message::String
    headers::Dict{String, String}
    body::String
end

HTMLResponse(body::String) = HTMLResponse(200, 
                             "OK",
                             Dict("Content-Type" => "text/html"), 
                             body)

HTMLResponse(status::Int, message, body::String) = HTMLResponse(status,
                                      message, 
                                      Dict("Content-Type" => "text/html"), 
                                      body)
struct TextResponse <: HTTPResponse
    status::Int
    message::String
    headers::Dict{String, String}
    body::String
end

TextResponse(body::String) = HTMLResponse(200, 
                             "OK",
                             Dict("Content-Type" => "text/plain"), 
                             body)

TextResponse(status::Int, message::String, body::String) = HTMLResponse(status,
                                      message, 
                                      Dict("Content-Type" => "text/plain"), 
                                      body)
function add_header(res::HTTPResponse, name::String, value::String)
    res.headers[name] = value
end


struct Route
    path
    handler::Function
    methods
    path_parts
    
    function Route(path, handler, methods)
        path_parts = split(path, "/", keepempty=false)
        new(path, handler, methods, path_parts)
    end
end


function matches(route::Route, req::Request)
    if req.method ∉ route.methods
        return false
    end
   
    if (route.path == req.path)
        return true
    end
    compare_parts = split(req.path, "/", keepempty=false)
  
    if (length(compare_parts) != length(route.path_parts))
        return false
    end
    for i=2:length(compare_parts)
        if (route.path_parts[i][1] == '<' && route.path_parts[i][end] == '>')
            push!(req.args, urldecode(compare_parts[i]))
        elseif (route.path_parts[i] !=  compare_parts[i])
            return false
        end 
    end
    true
end

struct Microdot
    routes
    function Microdot()
        new([])
    end
end

function run(app::Microdot)
    server = listen(2000) 
    while true
        sock = accept(server)
        (method, url, protocol) = split(readline(sock), " ")
        req = Request(String(method), String(url), String(protocol))
        
        #=
        Parse the header section
        =#
        while true
            header_line = readline(sock)
            if (header_line == "")
                break
            end
            (name, value) = split(header_line, ":")
            req.headers[name] = value[2:end]
        end
        
        #= 
        Body of the request
        =#
        if haskey(req.headers, "Content-Length")
            content_length = parse(Int, req.headers["Content-Length"])
            req.raw_data = read(sock, content_length)
            req.body = String(copy(req.raw_data))
        end
        
        #= 
        Form Data
        =#
        if haskey(req.headers, "Content-Type")
            if (req.headers["Content-Type"] == "application/x-www-form-urlencoded")
                req.form  = parse_query_string(req.body)
            end
        end
        
        route_found = false
        for route in app.routes
            if (matches(route, req))
                res = route.handler(req, req.args...)
                route_found = true
            end
        end
        
        if !(route_found)
            res = HTMLResponse(404, "Not Found", "<h2>Not Found</h2>")
        end
        
        add_header(res, "Content-Length", "$(length(res.body))")
    
        write(sock, "HTTP/1.1 $(res.status) $(res.message)\r\n")
        write(sock, "Server: Microdot.jl\r\n")
        
        for (name, value) in res.headers
            write(sock, "$(name): $(value)\r\n")
        end
            
  
        write(sock, "\r\n")
        write(sock, res.body)

        close(sock)
    end
end

function route(app::Microdot, path, handler, methods)
    push!(app.routes, Route(path, handler, methods))
end


function index(req::Request)
    return HTMLResponse("<p>Hello World</p>")
end

function hello(req::Request, name)
    return TextResponse("<p>Hello $(name)</p>")
end


app = Microdot()
route(app, "/", index, ["GET"])
route(app, "/hello/<user>", hello, ["GET"])
run(app)
