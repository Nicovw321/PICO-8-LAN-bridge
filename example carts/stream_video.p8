pico-8 cartridge // http://www.pico-8.com
version 43
__lua__

-- coordinator demo
-- (for centralized tasks)
-- video from the coordinator
-- is sent to the other carts

-- the first cart to enter the
-- server (with id 1) will be
-- assigned the coordinator role

-- the coordinator normally has
-- special tasks or resources
-- so that the data / processing
-- is not so decentralized



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

-- start cart sending packets
-- to avoid a deadlock
local send_clock=true

local connection = false
local connected = false

local self_id = 0
local carts = {}

local write_loc = 0

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
			
			-- if cart 1, the coordinator
			-- disconnects, then end
			-- the connection
			
			if data[1] == 1 then
				-- disconnect (255)
				send_packet(0,255)
			end
			
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
	
	if self_id and self_id!=1 then
		if #data==1 then
			write_loc = 0
		else
			poke(write_loc+0x6000, unpack(data))
			write_loc+=#data
		end
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

flip()

?"connected"

local x,y = 0,0

-- get number of carts (2)
send_packet(0,2)

-- get own id (3)
send_packet(0,3)

while connected do
	if self_id and self_id==1 then
		-- draw some graphics as the
		-- coordinator
		cls(1)
		circfill(t()*30%192-32,64,t()*5%32,rnd(16))
	end
	
	if btnp(1) then
		-- disconnect (255)
		send_packet(0,255)
	end
	
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
		-- or not (seen above)
		
		if self_id and self_id==1 then
			
			-- if we're at the start,
			-- broadcast custom
			-- syncronization packet
			
			-- this packet does not read
			-- the null byte (0)
			-- but this protocol does
			-- not let you send empty
			-- packets so we add a 1
			-- byte padding
			
			if write_loc==0 then
				send_packet(255,0)
			end
			
			-- divide screen data in
			-- packets of 256 bytes each
			
			-- do not send all data at
			-- once due to cpu usage
			
			for i=1,8 do
				send_packet(255,peek(write_loc+0x6000,256))
				write_loc+=256
				write_loc%=0x2000
			end
		else
			
			-- send heartbeat (4) if not
			-- streaming video to not
			-- get timed out
			send_packet(0,4)
		end
	end
	
	cart_io()
	
	
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
