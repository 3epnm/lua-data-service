function split (s, delim)

  assert (type (delim) == "string" and string.len (delim) > 0,
          "bad delimiter")

  local start = 1
  local t = {}  -- results table

  -- find each instance of a string followed by the delimiter

  while true do
    local pos = string.find (s, delim, start, true) -- plain find

    if not pos then
      break
    end

    table.insert (t, string.sub (s, start, pos - 1))
    start = pos + string.len (delim)
  end -- while

  -- insert final one (after last delimiter)

  table.insert (t, string.sub (s, start))

  return t
 
end -- function split

-- trim leading and trailing spaces from a string
function trim (s)
  return (string.gsub (s, "^%s*(.-)%s*$", "%1"))
end -- trim

-- convert + to space
-- convert %xx where xx is hex characters, to the equivalent byte
function urldecode (s)
  return (string.gsub (string.gsub (s, "+", " "), 
          "%%(%x%x)", 
         function (str)
          return string.char (tonumber (str, 16))
         end ))
end -- function urldecode

-- process a single key=value pair from a GET line (or cookie, etc.)
function assemble_value (s, t)
  assert (type (t) == "table")
  local _, _, key, value = string.find (s, "(.-)=(.+)")

  if key then
    t [trim (urldecode (key))] = trim (urldecode (value))
  end -- if we had key=value

end -- assemble_value