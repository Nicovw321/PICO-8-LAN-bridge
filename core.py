import subprocess
import sys
import socket
import threading

PICO8 = r"C:\Program Files (x86)\PICO-8\pico8.exe"

# PACKET IDs:
# These packet IDs are requests/commands sent to "cart" ID 0, that communicate directly with the LAN host python script (the server), or the LAN client python script (the one that launches PICO-8).
# These give a bit more control to the carts, giving them the ability to listen for carts that join/leave, to get all the carts that are in the server, and to choose which server to connect to (as well as disconnecting from it)

SCRIPT_PACKET_JOIN               = 0
# This packet ID should only be sent by the server and it signals which cart ID just joined the server (giving the cart ID as the only argument).

SCRIPT_PACKET_LEAVE              = 1
# This packet ID should only be sent by the server and it signals which cart ID left the server (giving the cart ID as the argument).

SCRIPT_PACKET_REQUEST_CART_IDS   = 2
# This packet ID can be sent by the cart to get all the cart IDs that are connected to the server. The server will echo back the same packet ID with the IDs of the carts (including the cart itself)

SCRIPT_PACKET_REQUEST_SELF_ID    = 3
# This packet can be sent by the cart to get its own ID. The server will echo back the same packet ID with the ID.

SCRIPT_PACKET_REQUEST_SEND_LIVE  = 4
# This is a heartbeat command should always be sent to signal the server that the cart is active. The server echoes this packet ID back.

SCRIPT_PACKET_REQUEST_CONNECT_IP = 254
# This packet ID is not sent to the LAN host.
# It's communicated directly to the client python script and signals the cart wants to join a server.
# The next bytes become the ip (as a string) the cart wants to connect to (eg: "192.168.1.70")

# The script echoes a packet with the same ID, with a 1 or a 0 signaling if the script was able to connect to it.

SCRIPT_PACKET_REQUEST_DISCONNECT = 255
# This packet ID sends a request to the LAN client to disconnect. It echoes the same packet back after disconnecting.

# If the client was kicked, or if the server crashes/shuts down, this packet is sent to signal the cart that the connection is over.

def create_instance(CART_IO, args):
    if args is None:
        args = []
    
    if CART_IO is None:
        cart = subprocess.Popen(
            [PICO8] + args,
            stdout=subprocess.PIPE,
            stdin=subprocess.PIPE,
            stderr=sys.stderr,
            bufsize=0,
        )
    else:
        cart = subprocess.Popen(
            [PICO8, "-run", CART_IO] + args,
            stdout=subprocess.PIPE,
            stdin=subprocess.PIPE,
            stderr=sys.stderr,
            bufsize=0,
        )
    return cart

def attach_thread(function,args):
    thread = threading.Thread(
        target=function,
        args=args,
        daemon=True
    )
    
    return thread



def receive_bytes_from_connection_safe(connection, num_bytes): # safe because it's possible recv returns a byte array smaller than num_bytes and this function fixes that
    output = []
    while len(output)<num_bytes:
        try:
            data = connection.recv(num_bytes-len(output))
        except ConnectionResetError:
            data = None
        
        if not data:
            return
        
        if data == b'': # if it's empty this means the connection is dead and we should return a None
            return
        
        output = output + list(data)
    
    return bytes(output)


def convert_cart_packets_to_bytes_to_host(packets): # when sending packets to the host, the subject is called "receiver" on the LAN client
    output = []
    
    output.append(len(packets))
    
    for packet in packets:
        output.append(packet["receiver"])
        
        output.append(len(packet["data"])-1)
        
        # concatenate packet data
        output = output + list(packet["data"])
    
    return bytes(output)

def convert_cart_packets_to_bytes_to_client(packets): # when sending packets to a client, the subject is called "sender" on the LAN host
    output = []
    
    output.append(len(packets))
    
    for packet in packets:
        output.append(packet["sender"])
        
        output.append(len(packet["data"])-1)
        
        # concatenate packet data
        output = output + list(packet["data"])
    
    return bytes(output)

def convert_bytes_to_cart_packets(connection):
    num_packets = receive_bytes_from_connection_safe(connection,1)
    
    if not num_packets:
        return
    
    num_packets = num_packets[0]
    
    output = []
    
    for _ in range(num_packets):
        subject = receive_bytes_from_connection_safe(connection,1)[0]
        packet_size = receive_bytes_from_connection_safe(connection,1)[0]+1
        data = receive_bytes_from_connection_safe(connection,packet_size)
        
        output.append({
            "subject": subject, # can be sender or receiver depending on if it's the client or the server who called this function
            "data": data
        })

    return output
