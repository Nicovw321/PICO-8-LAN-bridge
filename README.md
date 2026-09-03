# PICO-8 LAN Bridge

A proof-of-concept networking bridge that allows multiple PICO-8 instances to communicate with each other in the same LAN network.

If you wanted to play multiplayer on vanilla PICO-8, you have to use the same computer on split screen, but that can quickly reduce your viewable area considering the resolution (128x128). This project aims to fix these limitations, letting each player play on their own computer, while still making it "feel" like PICO-8 (it does not provide any tooling that helps bypass the CPU, RAM, tokens, character size, or compressed size limitations).

## Requirements

* Python 3.9.0 or newer
* PICO-8 0.2.7 or newer

## Installation & Usage

### 1. Clone the repository
```
git clone https://github.com/user/repo.git
cd repo
```

### 2. Set up the PICO-8 path on core.py

By default it's set to ``C:\Program Files (x86)\PICO-8\pico8.exe`` and you can change it if PICO-8 was installed somewhere else.

### 3. Run LAN_host.py / LAN_client.py

* To start a server, you execute LAN_host.py. Your local IP will be made available for other carts in the same network to connect to.

* To start a PICO-8 cartridge with LAN capabilities, you execute LAN_client.py. This will create a PICO-8 instance that will let you load a cartridge from SPLORE / your local files as usual. You can run any normal cartridge in this state, or you can run the example cartridges in this repository to experience PICO-8 LAN.

## Protocol details

Every PICO-8 cart that utilizes this bridge must communicate to it through STDIO (Channel 0x804 and 0x805 of [Serial](http://pico8wiki.com/index.php?title=Serial#Reading_and_writing)).

The protocol is relatively simple.

Packets are sent from the cartridge to the bridge (and vice versa) in bundles of 0-255 packets, and every packet must contain between 1 and 256 bytes of data (excluding the metadata).

Every 15th of a second you must send a single bundle of packets, and when you do so, you immediately receive one back from the bridge.

The bundle contains 1 byte for the number of packets to send, then the following bytes is the packet data.

Every packet contains:

* The cart ID (source or sender), as a single byte
* The data size as a single byte (it signals a size of 1-256 bytes)
* The data as raw bytes (it must be between 1 and 256 bytes)

### Cart IDs

When a cartridge joins a server, it gets assigned an ID. This ID can go from 1 to 254.

When sending a packet, the cart ID inside the metadata of the packet should point to the receiver, the cartridge that you want to send the packet to.

When receiving a packet, the cart ID points to the sender, the cartridge that sent you that packet.

The bridge automatically swaps sender/receiver ID during STDIO input/output, so the cartridge can safely assume any packets that it receives contains a **sender** and any packets it sends should contain a **receiver**.

Normally, the channel IDs are incremental. If two carts enter an empty server, they will be assigned the IDs 1 and 2 respectively. But if a cart leaves the server, the next one to enter will not get ID 3, instead the lowest available ID will be given (1 in this case).

If a cart with channel ID 2 left but 1 remained in the server, then the next cart will get the ID 1.

If instead, cart 1 left and 2 remained in the server, then the next one to join will get the ID 2.

### Special "cart" IDs

There are two special "cart" IDs that should not be populated by any carts: ID 0 and 255.

### Cart ID 255

Sending packets to "Cart" ID 255 broadcasts to all other players (everyone except yourself, ID 0, and ID 255).

### Cart ID 0

"Cart" ID 0 is a direct line of communication with the bridge. Every cart can send commands to the bridge, and the bridge can send data back.

This cart ID uses the first byte of the data inside each packet to represent different actions / events (referred to as command IDs):

#### Command ID 0 (Cart Join):

This is an event that the script will broadcast when a new cart has connected to the server.
As an argument (the byte after the command ID), it will provide its cart ID.

#### Command ID 1 (Cart Leave):

Similar to ID 0, this is an event that the script will broadcast to signal which cart *just* left the server.

#### Command ID 2 (Request cart IDs):

This is a command the that can be used to get all of the carts that are currently connected in the server.

When a cart sends this command, the server will echo back a new packet with the same command ID (ID 2) that also holds a list of all the cart IDs currently in the sever, including the cart ID who sent the command.

#### Command ID 3 (Request own cart ID):

This is a command a cartridge sends to get its own cart ID.

When a cart sends this command, the server will echo back a new packet with the same command ID (ID 3) alongside its own cart ID.

#### Command ID 4 (Heartbeat):

This is a heartbeat command a cart sends to tell the server that it is still running. Without it, there's a chance the server times out the connection. It is not strictly required if you're already actively sending packets to the server, but it is still recommended to avoid future headaches.

When a cartridge sends this command, the server will echo back the same command ID (ID 4) with no other data.

#### Command ID 254 (Connect to server):

This is a special command that talks to the client Python script (not the server), and it's a request to connect to a server.

The cartridge must give an IP to connect to. This IP must be passed as a string stored on the same packet, located after the command ID, and the end of the string is dictated by the end of the packet (not null nor a length byte).

The client will return a 1 if the connection was succesfull, and a 0 if it failed.

#### Command ID 255 (Disconnect from server):

This is a special command/event that the client Python script listens to when either the server or the cartridge disconnects.

If the cartridge is the one that wants to disconnect, then the cartridge must send a command of this ID (255). The python script will echo this command back when it succesfully disconnected from the server.

On the other hand, if the server kicks a cartridge, then the client Python script will send an event with this ID (255) telling the cartridge the connection was terminated.

## Implementing the Protocol

To implement this protocol, it is as simple as copying tab 0 of any of the example carts. Those contain the three most important functions:

1. **send_packet(receiver, ...):** Temporarily places any packets you're going to send onto a queue. 
2. **receive_packet(sender, data):** Executed when a new packet is received. Do not call this function directly unless you know what you're doing, normally this function should only be called by cart_io().
3. **cart_io():** Communidates with the bridge directly, sending and receiving packets (alternating per frame). While sending packets, it takes at most 255 packets from the queue and sends them to STDOUT, and while it's receiving a packet, it calls the function ``receive_packet()`` for each one it receives from STDIN.

The function ``receive_packet(sender, data)`` should be edited to parse all data other carts sent to it. Because keep in mind, this protocol only lets you send raw bytes between carts, so you have to make your own protocol to encode and decode those raw bytes. But if you want an easier time with this protocol, you can use the functions inside the example cart **chat.p8** that lets you serialize/deserialize data you send, basically letting you transfer tables, strings, numbers, and booleans between carts (you will need to copy tab 1 as well). It also lets you send packets of any size... well, up to ~64k (64512 more specifically), but it is unlikely you will reach that limit.

**WARNING:** Do not run your cartridge with \_update / \_update60 / \_draw. For some reason, packets that take several frames to send can get corrupted / truncated if the cartridge uses PICO-8's most common update functions. If you design your code smartly, you can still use \_update & \_draw if you avoid *ever* lagging your game, but I recommend instead using an infinite loop which avoid these problems:
```lua
while true do
    holdframe() -- undocumented function to avoid flicker when lagging
    cart_io() -- function responsible for handling network packets
    
    -- game logic here...
    
    -- draw logic here... (or you can merge game and draw logic together)
    
    flip() -- wait one frame
end
```

Infinite loops, compared to \_update / \_draw, have two problems that must be pointed out:
1. ``btnp`` can fail to detect button presses if the player presses it in a lag frame.

2. [Mouse delta / pointer lock](http://pico8wiki.com/index.php?title=Stat#{30%E2%80%A639}_Mouse_and_Keyboard) feature will detect a slower movement when the game is lagging.

To fix btnp missing button presses, you can craft your own btnp implementation, or use mine.

You can implement this not-so-accurate one (that does not repeat buttons and does not return a bitfield) that is efficent on tokens (68 tokens):

<details>
<summary>INACCURATE BTNP IMPLEMENTATION</summary>

```lua
---- put this on init ----

local button_timings={}

for p=0,7 do
	button_timings[p]=split"0,0,0,0,0"
	button_timings[p][0]=0
end


--------------------------

function btnp_update()
	for player_id, player_buttons in next,button_timings do
		for button_id, timing in next,player_buttons do
			-- add 1 if btn poll is true, reset if false
			player_buttons[button_id]-=btn(button_id,player_id) and -1 or timing
		end
	end
end

function btnp(button_id,player_id)
	-- detect first frame (when timer is at 1)
	return button_timings[player_id or 0][button_id]==1
end

-- implementation:

_set_fps(30) -- or 60 if you want

while true do
	holdframe() -- avoids flicker
	
	btnp_update() -- REMEMBER TO PUT THIS!
	
	-- your update code here --
	
	-- (this is a test to show its function)
	cls()
	for i=0,5 do
		?btnp(i),0,i*8,7
	end
	
	?btnp(),0,56,7 -- this is not implemented!
	
	flip()
end
```

</details>

---

Or you can use this one that is 99.9999% accurate to the original like in PICO, though it uses more tokens (220):

<details>
<summary>ACCURATE BTNP IMPLEMENTATION</summary>

```lua
---- put this on init ----

local button_timings={}
local button_presses={}

for p=0,7 do
	button_timings[p]=split"0,0,0,0,0"
	button_timings[p][0]=0
	button_presses[p]={}
end

local frame_skips=1


--------------------------

function btnp_update()
	-- custom delay
	local delay=@0x5f5c
	
	if(delay==0)delay=15 -- default: 15
	
	-- custom interval
	local interval=@0x5f5d
	
	if(interval==0)interval=4 -- default: 4
	
	for player_id, player_buttons in next,button_timings do
		for button_id, timing in next,player_buttons do
			-- add 1 if btn poll is true, reset if false
			player_buttons[button_id]-=btn(button_id,player_id) and -1 or timing
			
			local pressed=false
			
			-- if first frame pressed,
			-- then mark frame as pressed
			if timing==1 then
				pressed=true
			else
				local deltatime=30/(stat"7"/frame_skips)
				
				-- pico-8 specific btnp timing
				-- and fixed slowdown when
				-- lagging
				
				local r=timing*deltatime-delay+interval
				
				pressed = r>0 and r>interval and delay!=255
				
				if pressed then
					-- add 0x.0001 to avoid
					-- the upper timing==1 if
					-- from occurring again
					-- (if the interval was
					-- bigger than delay)
					player_buttons[button_id]-=interval/deltatime+0x.0001
				end
			end
			button_presses[player_id][button_id] = pressed
		end
	end
end

function btnp(button_id,player_id)
	
	local function poll(button_id,player_id)
		return button_presses[player_id][button_id]
	end
	
	-- if id is not nil, return
	-- specific button
	if button_id then
		return poll(button_id,player_id or 0)
	end
	
	-- if it is nil, return
	-- bitfield of both player 0 and 1
	
	local b=0
	for i=0,5 do
		b>>=1
		b|=tonum(poll(i,0))
		b|=tonum(poll(i,1))<<8
	end
	return b<<5
end

-- implementation:

_set_fps(30) -- or 60 if you want

while true do
	holdframe() -- avoids flicker
	
	btnp_update() -- REMEMBER TO PUT THIS!
	
	-- your update code here --
	
	-- (this is a test to show its function)
	cls()
	for i=0,5 do
		?btnp(i),0,i*8,7
	end
	
	?btnp(),0,56,7
	
	-- always have this at the end of the loop
	frame_skips = (stat(1)&-1)+1
	flip()
end
```

</details>

(The only inaccuracies from the implementation above is when dealing with framerates other than 15, 30 or 60, the function won't exactly break, but the timing won't be 100% the same as the original btnp function)

---

To fix mouse delta (if you need it in your game and your game is particularly laggy) you can use this code (uses 24 tokens):

<details>
<summary>MOUSE DELTA FIX</summary>

```lua
---- put this on init ----

local frame_skips=1

--------------------------

function get_mouse_delta_xy()
	return stat"38"*frame_skips,stat"39"*frame_skips
end

-- implementation:

_set_fps(30) -- or 60 if you want

poke(0x5f2d, 5)

while true do
	holdframe() -- avoids flicker
	
	-- your update code here --
	
	-- (this is a test to show its function)
	cls()
	
	local mx,my=get_mouse_delta_xy()
	
	line(64,64,64+mx/4,64+my/4,7)
	
	-- always have this at the end of the loop
	frame_skips=(stat"1"&-1)+1
	flip()
end
```

</details>

So keep those in mind.



## Examples

There are three example carts inside the ``example carts`` folder.

1. **game.p8:** A simple "game" that represents each player as a ball that they can move around, showing how to handle players joining / leaving and broadcasting packets.

2. **stream_video.p8:** A demonstration that shows how to designate a cartridge as the leader / coordinator. The leader / coordinator in this case is the one streaming video data while the others can only watch.

3. **chat.p8**: A demonstration of peer-to-peer networking, where you can type messages to tell it to everyone (broadcast packets) or /msg [cart_id] [message] to send direct messages to another cartridge. This version also has special code that sends and receives *tables* instead of raw bytes, for the coder to have an easier time working with messages.

## FAQ

**PICO-8 keeps hanging. Why is this happening?**

This can happen if the 15hz clock wasn't properly implemented. If you run your game at 30fps, you can run a 2-frame clock:

```lua

local clock = true

---- inside cart_io() ----

    if clock then
        -- send data...
    end

    if not clock then
        -- receive data...
    end

    clock = not clock

--------------------------

```

If you run your game at 60fps, you run a 4-frame clock:

```lua
local clock = 0

_set_fps(60) -- set custom fps

---- inside cart_io() ----
    if clock==0 then
        -- send data...
    end

    if clock==2 then
        -- receive data...
    end

    clock += 1
    clock %= 4
--------------------------
```

If this does **not** fix your problem, it can be that your STDIN/STDOUT functions are broken, as any problem with the implementation can immediately cause a deadlock. Try to use the code from the example carts, and if those didn't work, [open a discussion.](https://github.com/yourusername/repo/discussions)

**How do I know my server's IP address?**

On windows, you can open the commandline and type ``ipconfig`` then press enter. This will provide you a bunch of IP addresses, you need to use the one called "IPv4 Address" (starts with 192.168.X.X)

**What if I don't want to host on LAN only?**

In that case, I cannot help you.

But you can do the same trick done in Minecraft: Use VPNs. You can search for a Minecraft tutorial that tells you how to connect two computers with a VPN and instead of launching Minecraft and hosting on LAN, you run LAN_host.py and wait for your friends to enter the server. **But be careful with what tutorials you find out there. Do proper virus checks, check comment sections, see if the links are the real ones, and search online for security risks!**

For which VPNs to use, I recommend LogMeIn Hamachi or Radmin VPN as these worked for me in the past. **But be careful and search if any of these have vulnerabilities. Today it might be safe, but tomorrow is another story.** For that, don't keep these always turned on.

I want to make this clear that this project was **NOT** made for hosting public servers. To my knowledge, it is not possible to do RCE, but the server can still be easily crashed if someone really wanted to. This was made so you can play with your friends *only*. And please, do **not** expose port 5000 to the internet. There is no authentication, no encryption, and having an open port on your home computer can be incredibly dangerous.

## Known issues

1. Latency can be high, around 100-300ms in my network. The packets are not stable, sometimes lagging for multiple frames. But I don't know if that's a problem with my connection or if it's a limitation of this protocol.

2. Moving the PICO-8 window around the screen can cause time outs and create latency. Time outs are impossible to fix, as this is a limitation from PICO-8 itself, but the latency could be a bug in my implementation. I do not know how exactly it's happening and I have been unable to fix it.

3. PICO-8's STDIO implementation is buggy. \_update can break packets sent through STDIO so an infinite loop + ``flip()`` must be used for games that implement this bridge.

4. Stopping a cartridge while it's in the middle of sending a packet can corrupt every single packet that's sent afterwards. This has been half-fixed by the script automatically closing and re-opening the PICO-8 instance (which also avoids a deadlock and avoids forcing the user to terminate the program with task manager), though this means you should **always** edit your game in an external editor, or on a second PICO-8 instance, to avoid losing data if packets ever corrupt. CTRL-R can load external changes so you don't need to ``load cartridge.p8`` every time you change something.

5. Pressing CTRL-R while the cartridge is running can send corrupted packet data to the python script, again causing an automatic game re-launch to avoid further corruption.
