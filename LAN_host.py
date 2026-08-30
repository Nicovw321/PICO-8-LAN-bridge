import core
import time
import queue
import socket
import threading

MAX_CARTS = 250 # for safety 250 is the max

carts = {}

packet_received_queue = {}
packet_sending_queue = {}

connections = {}

def parse_command(packet):
    command_id = packet["data"][0]
    
    output = [command_id]
    if command_id == core.SCRIPT_PACKET_REQUEST_CART_IDS:
        output = output + list(carts.keys())
    elif command_id == core.SCRIPT_PACKET_REQUEST_SELF_ID:
        output.append(packet["sender"])
    elif command_id == core.SCRIPT_PACKET_REQUEST_SEND_LIVE:
        # don't return: this will echo back the same command ID
        pass
    else:
        return
    
    packet_sending_queue[packet["sender"]].put({
        "sender": 0,
        "data": bytes(output)
    })

def send_packet(receiver, packet, packet_queue):
    if receiver==0:
        parse_command(packet)
    elif receiver==255:
        broadcast(packet)
    else:
        try:
            packet_queue[receiver].put(packet)
        except KeyError:
            pass # to prevent erros if a cart communicates with one that is leaving/has already left

def broadcast(packet):
    for cart_id in list(carts.keys()):
        if cart_id == packet["sender"]:
            continue
        send_packet(cart_id, packet, packet_sending_queue)

join_kick_lock = threading.Lock()

def new_cart(connection):
    with join_kick_lock:
        
        already_exists_id = next(
            (key for key, value in carts.items() if value == connection),
            None
        )
        if already_exists_id:
            return
        
        for id in range(1,MAX_CARTS+1): # range 1-MAX_CARTS
            if id not in carts:
                
                carts[id] = connection
                
                packet_sending_queue[id] = queue.Queue()
                packet_received_queue[id] = queue.Queue()
                return id

def kick_cart(cart_id):
    with join_kick_lock:
        if cart_id not in carts:
            return
        
        broadcast({
            "sender": 0,
            "data": bytes([core.SCRIPT_PACKET_LEAVE, cart_id])
        })
        
        carts[cart_id].close()
        
        del carts[cart_id]
        
        del packet_sending_queue[cart_id]
        
        del packet_received_queue[cart_id]

def kick_all():
    for cart_id in list(carts.keys()):
        kick_cart(cart_id)

def connection_handler(connection, address):
    cart_id = new_cart(connection)
    if not cart_id:
        return
    
    broadcast({
        "sender": 0,
        "data": bytes([core.SCRIPT_PACKET_JOIN, cart_id])
    })
    
    while (cart_id in carts) and carts[cart_id] == connection:
        try:
            connection.settimeout(10)
            packet_list = core.convert_bytes_to_cart_packets(connection)
            connection.settimeout(None)
        except ConnectionAbortedError:
            packet_list = None
        except socket.timeout:
            packet_list = None
        
        if not packet_list:
            break

        for packet in packet_list:
            send_packet(packet["subject"], {
                "sender": cart_id,
                "data": packet["data"]
            }, packet_sending_queue)
    
    kick_cart(cart_id)
    
    print("Disconnected: ", address)

def accept_handler(server):
    while True:
        connection, address = server.accept()
        
        print("New Connection:", address)
        
        thread = core.attach_thread(connection_handler, (connection, address))
        thread.start()














print("starting server")

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

server.bind(("0.0.0.0", 5000))
server.listen()

thread = core.attach_thread(accept_handler, (server,))
thread.start()

try:
    hostname = socket.getfqdn()
    ip = socket.gethostbyname_ex(hostname)[2][0]
except:
    ip = "[Unable to find it, type ipconfig on a command prompt]"

print("Started server at IP",ip,"(write this IP on LAN_client.py)")

try:
    while True:
        connection_packets = {}
        
        for cart_id, cart in carts.items():
            sending_packets = []
            
            while len(sending_packets)<255:
                try:
                    packet = packet_sending_queue[cart_id].get_nowait()
                    sending_packets.append(packet)
                except queue.Empty:
                    break
            
            if len(sending_packets)>0:
                if cart not in connection_packets:
                    connection_packets[cart] = []
                
                connection_packets[cart] += sending_packets
            
        
        for connection, packet_list in connection_packets.items():
            try:
                connection.sendall(core.convert_cart_packets_to_bytes_to_client(packet_list))
            except OSError:
                pass
        
        time.sleep(1/15)
        
finally:
    for cart_id in list(carts.keys()):
        kick_cart(cart_id)