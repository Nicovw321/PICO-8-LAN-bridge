pico-8 cartridge // http://www.pico-8.com
version 43
__lua__

-- chat demo for showing off
-- broadcasts and sending direct
-- messages (packets)



-- wait 1 frame before sending
-- any data (i think this helps
-- avoiding crashes)
flip()

-- address to where the stdio
-- data will temporarily be
-- held. it will use at maximum
-- 256 bytes starting at this
-- address
local comm_addr = 0x4300

local send_packets = {}

local send_packet_id = 0

function send_packet(receiver,data,...)
	if receiver==0 then
		-- if the sender is 0, don't
		-- send a serialized table,
		-- just raw bytes
		assert(data,"packet size too small (minimum: 1 byte)")
		assert(#{...}<=255,"packet size too big (maximum: 256 bytes)")
		add(send_packets,{receiver,data,...})
		return
	end
	
	-- if the sender is 1 to 255
	
	local bytes = serialize(data)
	
	local total_size = #bytes
	
	-- if the total size is above
	-- 252 bytes, then we divide
	-- the packets in 252-byte
	-- chunks (252 bytes because
	-- we store an id, chunk size
	-- and chunk number to know
	-- which chunk belongs to which
	-- packet
	
	for i=1,total_size,252 do
		add(send_packets,{
			receiver,
			send_packet_id,
			send_packet_id>>8,
			i\252, -- current chunk id
			ceil(total_size/252), -- total chunks
			unpack(bytes,i,i+251) -- chunk data
		})
	end
	send_packet_id+=1
end

-- start cart sending packets
-- to avoid a deadlock
local send_clock=true

local connection = false
local connected = false

local self_id = 0
local carts = {}


local received_packets = {}

function receive_packet(sender,data)
	-- sender 0: special command
	if sender==0 then
		local command_id = deli(data,1)
		
		if command_id == 0 then
			-- cart connect
			local cart_id = data[1]
			add(carts,cart_id)
			
			new_message("cart "..cart_id," joined the chat","\fa","\fa")
		elseif command_id == 1 then
			-- cart disconnect
			local cart_id = data[1]
			del(carts,cart_id)
			new_message("cart "..cart_id," left the chat","\fa","\fa")
			
		elseif command_id == 2 then
			-- get cart ids
			carts = data
		elseif command_id == 3 then
			-- get own cart id
			self_id = data[1]
		elseif command_id == 254 then
			-- connection status
			connection = true
			connected = data[1]>0
		elseif command_id == 255 then
			-- kicked/disconnected
			connected=false
		end
		return
	end
	-- sender >= 1 <=254
	-- cart communication
	
	-- "data" variable is already
	-- deserialized and can be
	-- a table, string, boolean,
	-- or number. in this demo,
	-- it's always a table
	
	if type(data)!="table" then
		-- and if it's not a table,
		-- quit to avoid crashes
		return
	end
	
	if data.is_dm then
		-- direct message
		
		new_message("cart "..sender.." -> me: ",data.message,"\fc","\fc")
		
	else
		-- global message
		
		new_message(sender,data.message)
		
	end
end

function cart_io()
	if send_clock then
		-- send all packets to stdout
		-- (max is 255 per cycle)
		
		-- packet amount
		poke(comm_addr,min(#send_packets,255))
		serial(0x805,comm_addr,1)
		
		for i=1,min(#send_packets,255) do
			local packet=deli(send_packets,1)
			
			-- packet receiver
			poke(comm_addr,packet[1])
			
			-- length of data - 1
			poke(comm_addr+1,#packet-2)
			
			-- packet data
			local addr = comm_addr+2
			for i=2,#packet do
				poke(addr,packet[i])
				addr+=1
			end
			serial(0x805,comm_addr,addr-comm_addr)
		end
	end
	
	if not send_clock then
		-- receive packets from stdin
		
		-- number of packets
		serial(0x804,comm_addr,1)
		
		for i=1,@comm_addr do
			
			serial(0x804,comm_addr,2)
			
			local sender = @comm_addr
			local len = @(comm_addr+1)+1
			
			-- get packet data
			serial(0x804,comm_addr,len)
			
			local raw_data = {peek(comm_addr,len)}
			
			-- if the bridge sent the
			-- message, don't attempt
			-- to serialize it
			if sender==0 then
				receive_packet(sender,raw_data)
			elseif len>=4 then -- only receive packets of at least 4 bytes (enough to get packet id, chunk id, and max number of chunks
				-- key/id of the packet
				-- chunk we received
				local key = %comm_addr|(sender>>8)
				
				if not received_packets[key] then
					received_packets[key]={}
				end
				
				local tab=received_packets[key]
				
				-- store the raw bytes
				for i=0,251 do
					tab[i+raw_data[3]*252+1] = @(i+4+comm_addr)
				end
				
				-- when we get the last
				-- packet chunk, deserialize
				-- and run receive function
				if #tab==raw_data[4]*252 then
					receive_packet(sender,deserialize(tab))
					received_packets[key]=nil
				end
			end
			
		end
	end
	send_clock=not send_clock
end

-->8
--serialization/deserialization

function serialize(val)
	local output = {}
	local function insert(byte)
		add(output,byte)
	end
	
	local function s(val)
		if type(val)=="number" then
			-- serialize number
			insert"0x01"
			insert(val<<16)
			insert(val<<8)
			insert(val)
			insert(val>>8)
		elseif type(val)=="string" then
			-- serialize string
			insert"0x02"
			insert(#val)
			insert(#val>>8)
			for c in all(val) do
				insert(ord(c))
			end
		elseif count(val) then
			-- serialize table
			insert"0x03"
			local entries={}
			for k,v in pairs(val) do
				if not (type(k)=="number" and k>=0 and k<=len and k&-1==k) then
					add(entries,{k,v})
				end
			end
			insert(#entries)
			insert(#entries>>8)
			for entry in all(entries) do
				s(entry[1])
				s(entry[2])
			end
		elseif val==true then
			-- serialize true
			insert"0x04"
		elseif val==false then
			-- serialize false
			insert"0x05"
		else
			-- and if it's a function,
			-- coroutine, or nil, we
			-- serialize it as nil
			insert"0x00"
		end
	end
	
	s(val)
	
	return output
end

function deserialize(bytes)
	
	local i=0
	local function pull()
		i+=1
		return bytes[i]
	end
	
	local function s()
		local type=pull()
		
		if type==0x01 then
			--id 1: number
			return (pull()>>16)
			+ (pull()>>8)
			+ pull()
			+ (pull()<<8)
		elseif type==0x02 then
			-- id 2: string
			local len=pull()
			+ (pull()<<8)
			
			local tx=""
			for i=1,len do
				tx..=chr(pull())
			end
			
			return tx
		elseif type==0x03 then
			-- id 3: table
			local output={}
			local num=pull()+(pull()<<8)
			
			for i=1,num do
				output[s()]=s()
			end
			
			return output
		elseif type==0x04 then
			-- id 4: true
			return true
		elseif type==0x05 then
			-- id 5: false
			return false
		end
		-- id 0: nil
	end
	
	return s()
end

-->8



_set_fps(30)

poke(0x5f2d, 1)

local message_clock = 0
local message_str = ""
local message_x = 0

local messages = {}
local message_canvas_y = 0

function ease(target,current,speed)
	return (target-current)*speed
end

function new_message(sender,str,colorsender,colorstr)
	colorsender = colorsender or "\fb"
	colorstr = colorstr or "\f7"
	local sender_str
	
	if type(sender)=="string" then
		-- custom string
		
		sender_str = sender
	elseif type(sender)=="number" then
		-- cart id
		
		sender_str = "cart "..sender..": "
	else
		-- nothing
		
		sender_str = ""
	end
	
	local msg=sender_str..str
	
	-- divide message in 31 chars
	-- which is the maximum
	-- horizontally
	local divided = {}
	
	while msg!="" do
		add(divided,sub(msg,1,31))
		msg = sub(msg,32,-1)
	end
	
	-- delete "cart xxx:" string
	-- after dividing
	
	divided[1] = sub(divided[1],#sender_str+1,-1)
	
	-- add it back but with nice
	-- formatting
	
	divided[1] = colorsender..sender_str..colorstr..divided[1]
	
	for str in all(divided) do
		add(messages,str)
	end
end


local ip="localhost" -- your local server ip here (you can make some code to ask the user to write it too)
print("connecting to "..ip)

-- connect to ip (254)
send_packet(0,254,ord(ip,1,#ip))

while not connection do
	cart_io()
	flip()
end

if not connected then
	stop("could not connect")
end

flip()

?"connected"

local x,y = 0,0

-- get number of carts (2)
send_packet(0,2)

-- get own id (3)
send_packet(0,3)

while connected do
	if send_clock then
		-- reminder: if we are sending
		-- periodic packets, only send
		-- them when you're about to
		-- send data to stdio
		-- (in this case, when
		-- send_clock is true)
		-- or else you might send
		-- duplicate data.
		-- for one-off packet sends,
		-- like when when a player
		-- presses a button, it is
		-- fine to send the packet
		-- regardless if you're about
		-- to send them through stdio
		-- or not
		
		-- send heartbeat (4) to not
		-- get timed out
		send_packet(0,4)
		
	end
	
	poke(0x5f30,1)
	
	while stat(30) do
		local key = stat(31)
		
		if key=="\194" then
			printh(message_str,"@clip")
		elseif key=="\213" then
			-- pressed ctrl-v
			message_str..=stat(4)
			
		elseif key=="\8" then
			message_str = sub(message_str,1,-2)
		elseif key=="\r" then
			-- pressed enter: parse
			-- message
			
			-- don't send if empty
			if(message_str=="")break
			
			if message_str[1]=="/" then
				-- command
				
				local keywords=split(message_str," ")
				
				if keywords[1]=="/msg" then
					if tonum(keywords[2]) then
						-- reconstruct message without
						-- the first 2 keywords
						
						message_str = ""
						for i=3,#keywords do
							message_str..=keywords[i].." "
						end
						
						send_packet(keywords[2],{
							is_dm = true,
							message = message_str
						})
						
						new_message("me -> cart "..keywords[2]..": ",message_str,"\fc","\fc")
					else
						new_message(nil,"syntax error.","\f8","\f8")
					end
				elseif keywords[1]=="/quit" then
					-- disconnect (255)
					send_packet(0,255)
				else
					new_message(nil,"unknown command. supported:    /msg [cart_id] [message] or    /quit","\f8","\f8")
				end
				
			else
				-- normal message
				
				send_packet(255,{
					is_dm = false,
					message = message_str
				})
				
				new_message(self_id,message_str)
			end
			
			message_str = ""
		elseif ord(key)<=153 then
			message_str..=key
		end
	end
	
	-- handle stdio
	cart_io()
	
	message_clock+=1
	message_clock%=15
	
	cls()
	rect(0,0,127,127,7)
	rect(0,119,127,127,7)
	
	message_canvas_y+=ease(#messages*8,message_canvas_y,0.25)
	
	-- draw messages
	clip(0,0,127,119)
	for i,msg in ipairs(messages) do
		?msg,2,i*8-8+119-message_canvas_y
	end
	clip()
	
	-- draw query (is it called that? basically where the player can write text)
	?"> "..message_str..(message_clock>7 and "\f8_" or ""),message_x+0x2.ffff,121,7
	
	message_x+=ease(min(#message_str*-4+100,0),message_x,0.5)
	
	flip()
end

cls()
?"disconnected",7
