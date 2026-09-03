pico-8 cartridge // http://www.pico-8.com
version 43
__lua__

-- multiplayer demo
-- every player is a ball that
-- they can move around
-- packets are broadcasted




-- wait 1 frame before sending
-- any data (i think this helps
-- avoiding crashes)
flip()

poke(0x5f2d, 1)

_set_fps(30)

-- address to where the stdio
-- data will temporarily be
-- held. it will use at maximum
-- 256 bytes starting at this
-- address
local comm_addr = 0x4300

local send_packets = {}

function send_packet(receiver,...)
	add(send_packets,{receiver,...})
end


local connection = false
local connected = false

local self_id
local carts = {}

local balls = {}

function receive_packet(sender,data)
	-- sender 0: special command
	if sender==0 then
		local command_id = deli(data,1)
		
		if command_id==0 then
			-- new cart connected
			add(carts,data[1])
		elseif command_id==1 then
			-- cart disconnected
			del(carts,data[1])
			
			-- remove ball of that id
			balls[data[1]] = nil
		elseif command_id==2 then
			-- get cart ids
			carts = data
		elseif command_id==3 then
			-- get own cart id
			self_id = data[1]
		elseif command_id==254 then
			-- connection status
			connection = true
			connected = data[1]>0 -- if 1, connected. if 0, not connected
		elseif command_id==255 then
			-- kicked/disconnected
			connected=false
		end
		return
	end
	
	-- sender >= 1 <=254
	-- cart communication
	
	if #data == 2 then
		-- update ball position
		balls[sender]={x=data[1],y=data[2]}
	end
end

-- start cart sending packets
-- to avoid a deadlock
local send_clock=true

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
			
			receive_packet(sender,{peek(comm_addr,len)})
		end
	end
	send_clock=not send_clock
end


-->8
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
		
		-- broadcast x and y of ball
		-- you're controlling
		send_packet(255,x,y)
		
		-- send heartbeat to not
		-- get kicked
		send_packet(0,4)
	end
	
	cart_io()
	
	cls()
	
	x+=tonum(btn"1")-tonum(btn"0")
	y+=tonum(btn"3")-tonum(btn"2")
	
	for i,v in pairs(balls) do
		spr(i+16,v.x,v.y)
	end
	
	spr(self_id and self_id+16,x,y)
	
	?"number of players: "..#carts,0,122-6,7
	
	-- cart lists
	local text = ""
	for cart_id in all(carts) do
		text..=cart_id.." "
	end
	?text,0,122,7
	flip()
end

cls()
?"disconnected",7
__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00565600008888000099990000aaaa0000bbbb0000cccc0000dddd0000eeee0000ffff0000111100001111000022220000333300004444000055550000666600
0565676008888780099997900aaaa7a00bbbb7b00cccc7c00dddd7d00eeee7e00ffff7f001000710011117100222272003333730044447400555575006666760
0656565008888880099999900aaaaaa00bbbbbb00cccccc00dddddd00eeeeee00ffffff001000010011111100222222003333330044444400555555006666660
0565656008888880099999900aaaaaa00bbbbbb00cccccc00dddddd00eeeeee00ffffff001000010011111100222222003333330044444400555555006666660
0656565008888880099999900aaaaaa00bbbbbb00cccccc00dddddd00eeeeee00ffffff001000010011111100222222003333330044444400555555006666660
00656500008888000099990000aaaa0000bbbb0000cccc0000dddd0000eeee0000ffff0000111100001111000022220000333300004444000055550000666600
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
07777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
07777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
07777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
07777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
