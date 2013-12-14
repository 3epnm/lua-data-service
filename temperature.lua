json = require('json')
cgi  = require('cgi')
date = require('date')

local data_path = "test/tempdata"

function error (code, message) 
   local h = ""
   if code == 400 then
      h = "HTTP/1.1 400 Bad Request"
   end
   if code == 401 then
      h = "HTTP/1.1 401 Unauthorized"
   end
   if code == 404 then
      h = "HTTP/1.1 404 Not Found"
   end

   if uhttpd ~= nil then
      uhttpd.send(h .. "\r\n") 
      uhttpd.send("Access-Control-Allow-Origin: *\r\n")
      uhttpd.send("Content-Type: application/json\r\n\r\n")
      uhttpd.send('{ err: "' .. message .. '"}')
   else 
      print(h)
      print(message)
   end
end

function sanitize_request(query_string) 
   local request_data = { sensors = nil }
   local sensors = {}
   local has_sensor_filter = false
   local query = split(query_string, "&")
   for _, v in ipairs (query) do
      local _, _, key, value = string.find (v, "(.-)=(.+)")
      if key then
         key = trim (urldecode (key))
         value = trim (urldecode (value))

         if key == "from" or key == "to" then
            request_data[key] = date(urldecode (value))
         elseif key == "sensors" then
            has_sensor_filter = true
            for _, sensor in ipairs (split(urldecode (value), ";")) do
               sensors[sensor] = true
            end
         end
      end
   end

   if request_data.from == nil and request_data.to == nil then
      local t = os.time()
      local d = os.date('%Y-%m-%d', t)
      request_data.from = date(os.date('%Y-%m-%d', t) .. "T00:00:00Z")
      request_data.to = date(os.date('%Y-%m-%d', t) .. "T23:59:59Z")
   end
   if request_data.from == nil then
      request_data.from = date(request_data.to:fmt('%F') .. "T00:00:00Z")
   end
   if request_data.to == nil then
      request_data.to = date(request_data.from:fmt('%F') .. "T23:59:59Z")
   end
   if request_data.int == nil then 
      request_data.int = -1
   end
   if has_sensor_filter then
      request_data.sensors = sensors
   end

   return request_data
end

function response_insert_buffer(response, id, buffer)
   if not response.sensors[id] then
      response.sensors[id] = { label = id, count = 0, data = {} }
   end
   table.insert(response.sensors[id].data, { 
      (date.diff(buffer.start, date.epoch()):spanseconds() + (buffer.int / 2)) * 1000, 
      string.format("%.2f", (buffer.value / buffer.cnt))
   })
   response.sensors[id].count = response.sensors[id].count + 1
end

function handle_request(env)
   local query_string = ""
   if env.QUERY_STRING ~= nil then
      query_string = env.QUERY_STRING
   end

   local request_data = sanitize_request(query_string);

   if request_data.to < request_data.from then
      error(400, 'from time is bigger then to time')
      return
   end

   if request_data.int < 0 then
      request_data.int = math.floor(date.diff(request_data.to, request_data.from):spanminutes() / 3000)
      if request_data.int > 0 then
         request_data.int = request_data.int * 60
      end
   end

   local d = date.diff(request_data.to:fmt('%F'), request_data.from:fmt('%F')):spandays()
   local period = { request_data.from:fmt('%F') }
   local t = request_data.from:copy()
   while d > 0 do
      table.insert(period, t:adddays(1):fmt('%F'))
      d = d - 1
   end

   local response_data = { 
      from = date.diff(request_data.from, date.epoch()):spanseconds() * 1000, 
      to   = date.diff(request_data.to, date.epoch()):spanseconds() * 1000,
      int  = request_data.int,
      sensors = {}
   }

   local has_response = false
   local buffer = {}
   local cnt = 0
   for _, cur_date in ipairs (period) do
      cur_file = data_path .. "/" ..  cur_date .. ".dat"
      local f = io.open(cur_file,"r")
      if f then   
         for line in io.lines(cur_file) do
            local id = string.sub(line, 10, 25)
            if request_data.sensors == nil or request_data.sensors[id] ~= nil then
               local read_date = date(cur_date .. "T" .. string.sub(line, 1, 8) .. "Z")
               if read_date >= request_data.from and read_date <= request_data.to then
                  cnt = cnt + 1
                  if not buffer[id] then
                     buffer[id] = { start = read_date, cnt = 0, value = 0 }
                  end
                  
                  buffer[id].int = read_date:spanseconds() - buffer[id].start:spanseconds()
                  buffer[id].cnt = buffer[id].cnt + 1
                  buffer[id].value = buffer[id].value + tonumber(string.format("%.2f", string.sub(line, 26, string.len(line))))

                  if not response_data.sensors[id] or buffer[id].int >= request_data.int then
                     response_insert_buffer(response_data, id, buffer[id])
                     buffer[id] = nil
                     has_response = true
                  end
               end
            end
         end
      end
   end

   for id, cur_buffer in ipairs (buffer) do
      response_insert_buffer(response_data, id, cur_buffer)
   end

   if not has_response then
      error(404, 'no sensordata found for request')
      return
   else
      if uhttpd ~= nil then
         uhttpd.send("HTTP/1.0 200 OK\r\n")
         uhttpd.send("Access-Control-Allow-Origin: *\r\n")
         uhttpd.send("Content-Type: application/json\r\n\r\n")
         uhttpd.send(json.encode(response_data))
      else
         print(json.encode(response_data))
         --require('printr')
         --print(table.show(request_data, "request_data"))
         --print(table.show(response_data, "response_data"))
      end
   end
end

-- TESTS 
--local query_string = "from=2013-12-12T23:48:00Z&to=2013-12-12T16:37:04"
--local query_string = "from=2013-12-10T23:48:00Z&to=2013-12-14T16:37:04&sensors=1016D2C000080080;10978DB600080006"
--local query_string = "from=2013-12-14T00:00:00Z&to=2013-12-14T01:00:00&sensors=1016D2C000080080"
--local query_string = "from=2013-12-12T23:48:00Z&to=2013-12-14T16:37:04"
--local env = { QUERY_STRING = query_string }
if uhttpd == nil then
   handle_request({})
end