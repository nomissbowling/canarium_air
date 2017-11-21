--[[
------------------------------------------------------------------------------------
--  Canarium Air RPC Server module                                                --
------------------------------------------------------------------------------------
  @author Shun OSAFUNE <s.osafune@j7system.jp>
  @copyright The MIT License (MIT); (c) 2017 J-7SYSTEM WORKS LIMITED

  *Version release
    v0.1.1122   s.osafune@j7system.jp

  *Requirement FlashAir firmware version
    W4.00.01

  *Requirement Canarium Air version
    v0.1.1120 or later

------------------------------------------------------------------------------------
-- The MIT License (MIT)
-- Copyright (c) 2017 J-7SYSTEM WORKS LIMITED
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
------------------------------------------------------------------------------------
--]]

-- 外部モジュール
local band = require "bit32".band
local bor = require "bit32".bor
local bxor = require "bit32".bxor
local lshift = require "bit32".lshift
local extract = require "bit32".extract
local btest = require "bit32".btest
local schar = require "string".char
local sform = require "string".format
local rand = require "math".random
local shdmem = require "fa".sharedmemory
local jsonenc = require "cjson".encode

-- モジュールオブジェクト
cr = {}

-- バージョン
function cr.version() return "0.1.1122" end

-- デバッグ表示メソッド（必要があれば外部で定義する）
function cr.dbgprint(...) end


------------------------------------------------------------------------------------
-- Base64url function (RFC4648)
------------------------------------------------------------------------------------

-- Base64urlへエンコード
local b64table = {
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
    'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f',
    'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
    'w', 'x', 'y', 'z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '-', '_'}

function cr.b64enc(d)
  local b64str = ""
  local n = 1
  local m = #d % 3

  while n+2 <= #d do
    local b0,b1,b2 = d:byte(n, n+2)
    local chunk = bor(lshift(b0, 16), lshift(b1, 8), b2)
    b64str = b64str .. b64table[extract(chunk, 18, 6) + 1] .. b64table[extract(chunk, 12, 6) + 1]
      .. b64table[extract(chunk, 6, 6) + 1] .. b64table[extract(chunk, 0, 6) + 1]

    n = n + 3
  end

  if m == 2 then
    local b0,b1 = d:byte(n, n+1)
    local chunk = bor(lshift(b0, 16), lshift(b1, 8))
    b64str = b64str .. b64table[extract(chunk, 18, 6) + 1] .. b64table[extract(chunk, 12, 6) + 1]
        .. b64table[extract(chunk, 6, 6) + 1]
  elseif m == 1 then
    local b0 = d:byte(n)
    local chunk = lshift(b0, 16)
    b64str = b64str .. b64table[extract(chunk, 18, 6) + 1] .. b64table[extract(chunk, 12, 6) + 1]
  end

  return b64str
end


-- Base64urlをデコード
local rb64table = {
          nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
     nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
     nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,0x3e, nil, nil,
    0x34,0x35,0x36,0x37,0x38,0x39,0x3a,0x3b,0x3c,0x3d, nil, nil, nil,0x00, nil, nil,
     nil,0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,
    0x0f,0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,0x18,0x19, nil, nil, nil, nil,0x3f,
     nil,0x1a,0x1b,0x1c,0x1d,0x1e,0x1f,0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28,
    0x29,0x2a,0x2b,0x2c,0x2d,0x2e,0x2f,0x30,0x31,0x32,0x33, nil, nil, nil, nil, nil}

function cr.b64dec(s)
  local data = ""
  local n = 1
  local e = true
  
  s = s:gsub("%s+", "")
  local m = #s % 4
  if m == 2 then
    s = s .. "=="
  elseif m == 3 then
    s = s .. "="
  elseif m == 1 then
    return nil,"input data shortage"
  end

  while n+3 <= #s do
    local b0,b1,b2,b3 = s:byte(n, n+3)
    local c0 = rb64table[b0]
    local c1 = rb64table[b1]
    local c2 = rb64table[b2]
    local c3 = rb64table[b3]
    if not(c0 and c1 and c2 and c3) then e = false; break end
    local chunk = bor(lshift(c0, 18), lshift(c1, 12), lshift(c2, 6), c3)

    if b2 == 0x3d then
      if b3 ~= 0x3d then e = false; break end
      data = data .. schar(extract(chunk, 16, 8))
      break
    elseif b3 == 0x3d then
      data = data .. schar(extract(chunk, 16, 8), extract(chunk, 8, 8))
      break
    else
      data = data .. schar(extract(chunk, 16, 8), extract(chunk, 8, 8), extract(chunk, 0, 8))
    end

    n = n + 4
  end

  if not e then return nil,"invalid character" end
  return data
end


------------------------------------------------------------------------------------
-- Canarium RPC local function 
------------------------------------------------------------------------------------

-- 共有メモリ書き込み
local _update = function(dstr)
  shdmem("write", 512, #dstr+1, dstr.."\x00")
  --[[
  local str = shdmem("read", 512, 100)
  cr.dbgprint("> shdmem : "..str)
  --]]
end

-- 進捗表示処理（ファンクションの待避とヘッダ部の設定）
local prog_func,prog_txt = nil,""

local _setprog = function(key, id, cmd)
  if not key then
    if prog_func then
      ca.progress = prog_func
      prog_func = nil
      _update("")
    end
  else
    if not prog_func then
      prog_txt = sform('{"key":%5d,"id":%5d,"command":%3d,"progress":[', key, id, cmd)
      prog_func = ca.progress
    end
  end
end

-- カレントファイルパス変換
local cur_path = arg[0]:match(".+/")

local _getpath = function(fn)
  if fn:sub(1, 1) ~= "/" then
    if fn:sub(1, 2) == "./" then fn = fn:sub(3, -1) end
    fn = cur_path .. fn
  end
  return fn
end

-- バイト列から32bitワードを取得
local _get_word32 = function(s, n)
  return bor(lshift(s:byte(n, n), 24), lshift(s:byte(n+1, n+1), 16), lshift(s:byte(n+2, n+2), 8), s:byte(n+3, n+3))
end

-- バイト列から16bitワードを取得
local _get_word16 = function(s, n)
  return bor(lshift(s:byte(n, n), 8), s:byte(n+1, n+1))
end

-- データのチェックコード生成
local _checkcode = function (d)
  local x = 0
  for _,b in ipairs{d:byte(1, -1)} do
    x = bxor(b, bor(lshift(x, 1), (btest(x, 0x80) and 1 or 0)))
  end
  return band(x, 0xff)
end


-- CONFコマンド、FCONFコマンド実行
local _do_config = function(cstr)
  ca.progress = function(f, p1, p2)
    _update(prog_txt..sform("%3d,%3d]}", p1, p2))
  end

  return ca.config{
      file = _getpath(cstr:sub(2, -1)),
      cache = (cstr:byte(1, 1) == 0x80)
    }
end


-- IOWRコマンド実行
local _do_iowr = function(cstr)
  ca.progress = function(f, p1)
    _update(prog_txt..sform("%3d]}", p1))
  end

  ca.progress("", 0)

  local res = nil
  local avm,mes = ca.open{devid = cstr:byte(2, 2)}
  if avm then
    res,mes = avm:iowr(_get_word32(cstr, 3), _get_word32(cstr, 7))
    avm:close()
  end

  if res then ca.progress("", 100) end

  return res,mes
end

-- IORDコマンド実行
local _do_iord = function(cstr)
  ca.progress = function(f, p1)
    _update(prog_txt..sform("%3d]}", p1))
  end

  ca.progress("", 0)

  local res = nil
  local avm,mes = ca.open{devid = cstr:byte(2, 2)}
  if avm then
    res,mes = avm:iord(_get_word32(cstr, 3))
    avm:close()
  end

  if res then ca.progress("", 100) end

  return res,mes
end

-- MEMWRコマンド実行
local _do_memwr = function(cstr)
  ca.progress = function(f, p1)
    _update(prog_txt..sform("%3d]}", p1))
  end

  ca.progress("", 0)

  local res = nil
  local avm,mes = ca.open{devid = cstr:byte(2, 2)}
  if avm then
    res,mes = avm:memwr(_get_word32(cstr, 3), cstr:sub(7, -1))
    avm:close()
  end

  if res then ca.progress("", 100) end

  return res,mes
end

-- MEMRDコマンド実行
local _do_memrd = function(cstr)
  ca.progress = function(f, p1)
    _update(prog_txt..sform("%3d]}", p1))
  end

  ca.progress("", 0)

  local res = nil
  local avm,mes = ca.open{devid = cstr:byte(2, 2)}
  if avm then
    res,mes = avm:memrd(_get_word32(cstr, 3), _get_word16(cstr, 7))
    avm:close()
  end

  if res then ca.progress("", 100) end

  return res,mes
end


-- BLOADコマンド実行
local _do_bload = function(cstr)
  ca.progress = function(f, p1)
    _update(prog_txt..sform("%3d]}", p1))
  end

  local res = nil
  local avm,mes = ca.open{devid = cstr:byte(2, 2)}
  if avm then
    res,mes = avm:bload(_getpath(cstr:sub(7, -1)), _get_word32(cstr, 3))
    avm:close()
  end

  return res,mes
end

-- BSAVEコマンド実行
local _do_bsave = function(cstr)
  ca.progress = function(f, p1)
    _update(prog_txt..sform("%3d]}", p1))
  end

  local res = nil
  local avm,mes = ca.open{devid = cstr:byte(2, 2)}
  if avm then
    res,mes = avm:bsave(_getpath(cstr:sub(11, -1)), _get_word32(cstr, 7), _get_word32(cstr, 3))
    avm:close()
  end

  return res,mes
end

-- LOADコマンド実行
local _do_load = function(cstr)
  ca.progress = function(f, p1)
    _update(prog_txt..sform("%3d]}", p1))
  end

  local res = nil
  local avm,mes = ca.open{devid = cstr:byte(2, 2)}
  if avm then
    res,mes = avm:load(_getpath(cstr:sub(7, -1)), _get_word32(cstr, 3))
    avm:close()
  end

  return res,mes
end


------------------------------------------------------------------------------------
-- Canarium RPC command parser
------------------------------------------------------------------------------------

-- カレントパスの設定
function cr.setpath(path)
  if type(path) == "string" then
    if path:sub(1, 1) ~= "/" then
      if path:sub(1, 2) == "./" then path = path:sub(3, -1) end
      path = cur_path .. path
    end
    if path:sub(-1, -1) ~= "/" then path = path .. "/" end
    cur_path = path
  end

  return cur_path
end

-- コマンドパース
function cr.parse(query)
  local _do_command = function(q)
    if not q then
      return {rpc_version=cr.version(), lib_version=ca.version(), copyright="(c)2017 J-7SYSTEM WORKS LIMITED"},nil
    end

    local rp = cr.b64dec(q)

    -- query decode error
    if not rp then return nil,nil,"Parse error",-32700 end
    -- query packet error
    if #rp < 5 then return nil,nil,"Parse error",-32700 end

    local id = _get_word16(rp, 1)
    local dlen = rp:byte(3, 3)
    local ckey = rp:byte(4, 4)

    -- query data error
    if not(#rp == dlen+4 and ckey == _checkcode(rp:sub(5, -1))) then return nil,id,"Parse error",-32700 end

    --[[
    local s = "> decode :"
    for _,b in ipairs{rp:byte(1, -1)} do s = s .. sform(" %02x",b) end
    cr.dbgprint(s)
    --]]

    -- メソッド実行
    local key = rand(65535)
    local cmd = rp:byte(5, 5)
    local cstr = rp:sub(5, -1)
    local ecode = -32000
    local res,mes

    _setprog(key, id, cmd)

    if cmd == 0x10 then
      cr.dbgprint("> iowr")
      res,mes = _do_iowr(cstr)
    elseif cmd == 0x11 then
      cr.dbgprint("> iord")
      res,mes = _do_iord(cstr)
      if res then cr.dbgprint(sform(">  data : 0x%08x", res)) end
    elseif cmd == 0x18 then
      cr.dbgprint("> memwr")
      res,mes = _do_memwr(cstr)
    elseif cmd == 0x19 then
      cr.dbgprint("> memrd")
      res,mes = _do_memrd(cstr)
      if res then
        --
        local s = ">  data :"
        for _,b in ipairs{res:byte(1, -1)} do s = s .. sform(" %02x", b) end
        cr.dbgprint(s.." ("..#res.."bytes)")
        --]]
        res = cr.b64enc(res)
      end

    elseif cmd == 0x20 then
      cr.dbgprint("> binload")
      res,mes = _do_bload(cstr)
    elseif cmd == 0x21 then
      cr.dbgprint("> binsave")
       res,mes = _do_bsave(cstr)
    elseif cmd == 0x22 then
      cr.dbgprint("> hexload")
      res,mes = _do_load(cstr)

    elseif cmd == 0x80 or cmd == 0x81 then
      cr.dbgprint("> config")
      res,mes = _do_config(cstr)
    elseif cmd == 0x8f then
      cr.dbgprint("> confcheck")
      res = ca.config() and 1 or 0

    else
      mes = "Method not found"
      ecode = -32601
    end

    _setprog()

    if not res then return res,id,mes,ecode end
    return res,id
  end


  -- クエリのパースと実行
  local res,id,mes,ecode = _do_command(query)

  local t = {jsonrpc="2.0", id=id}
  if res then t.result = res else t.error = {code=ecode, message=mes} end

  return jsonenc(t)
end


------------------------------------------------------------------------------------
-- テスト用ファンクション
------------------------------------------------------------------------------------

-- クエリを生成
function cr.makequery(t)
  local _setavm = function(cmd, devid, addr)
    local s = schar(cmd, devid)
    for i=24,0,-8 do s = s .. schar(extract(addr, i, 8)) end
    return s
  end
  
  local pstr = ""
  local dev = t.devid or 0x55
  
  if t.cmd == "CONF" then
    pstr = schar(0x80) .. t.file

  elseif t.cmd == "FCONF" then
    pstr = schar(0x81) .. t.file

  elseif t.cmd == "CHECK" then
    pstr = schar(0x8f)

  elseif t.cmd == "IOWR" then
    if type(t.data) == "number" then
      pstr = _setavm(0x10, dev, t.addr) ..
        schar(extract(t.data, 24, 8), extract(t.data, 16, 8), extract(t.data, 8, 8), extract(t.data, 0, 8))
    else
      return nil,"invalid parameter"
    end
  
  elseif t.cmd == "IORD" then         
    pstr = _setavm(0x11, dev, t.addr)
  
  elseif t.cmd == "MEMWR" then
    if type(t.data) == "string" then
      pstr = _setavm(0x18, dev, t.addr) .. t.data
    else
      return nil,"invalid parameter"
    end
  
  elseif t.cmd == "MEMRD" then
    pstr = _setavm(0x19, dev, t.addr) ..
      schar(extract(t.size, 8, 8), extract(t.size, 0, 8))
  
  elseif t.cmd == "BLOAD" then
    pstr = _setavm(0x20, dev, t.addr) .. t.file
  
  elseif t.cmd == "BSAVE" then
    pstr = _setavm(0x21, dev, t.addr) .. 
      schar(extract(t.size, 24, 8), extract(t.size, 16, 8), extract(t.size, 8, 8), extract(t.size, 0, 8)) ..
      t.file
  
  elseif t.cmd == "LOAD" then
    pstr = _setavm(0x22, dev, t.addr) .. t.file
  
  else
    return nil,"invalid command"
  end
  
  if #pstr > 70 then return nil,"payload data too long" end
  
  local res = schar(extract(t.id, 8, 8), extract(t.id, 0, 8), #pstr, _checkcode(pstr)) .. pstr
  --[[
  local s = "packet :"
  for _,b in ipairs{res:byte(1, -1)} do s = s .. sform(" %02x",b) end
  cr.dbgprint(s)
  --]]
  return cr.b64enc(res)
end


return cr
