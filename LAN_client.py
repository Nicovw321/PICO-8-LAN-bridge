import socket
import threading
import core
import time
import queue

connection = None

PACKET_STATE_IDLE = 0
PACKET_STATE_RECEIVING_DATA = 1

packet_state = PACKET_STATE_IDLE
packet_start_time = None

packet_received_queue = queue.Queue()
packet_sending_queue = {}

def convert_cart_packets_to_bytes(packets):
    output = []
    
    output.append(len(packets))
    
    for packet in packets:
        output.append(packet["sender"])
        
        output.append(len(packet["data"])-1)
        
        # concatenate packet data
        output = output + list(packet["data"])
    
    return bytes(output)

def get_bytes_and_convert_to_cart_packets(get_bytes):
    global packet_state, packet_start_time
    
    packet_state = PACKET_STATE_IDLE
    
    num_packets = get_bytes(1)
    
    if not num_packets: # if num_packets is None it means there is no data to receive/convert
        return
    
    # to detect desynchronization
    packet_start_time = time.monotonic()
    packet_state = PACKET_STATE_RECEIVING_DATA
    
    num_packets = num_packets[0]
    
    output = []
    
    for _ in range(num_packets):
        receiver = get_bytes(1)[0]
        packet_size = get_bytes(1)[0]+1
        data = get_bytes(packet_size)
        
        output.append({
            "receiver": receiver,
            "data": data
        })

    return output

# receive data from host
def connection_handler():
    global connection
    while connection is not None:
        try:
            packet_list = core.convert_bytes_to_cart_packets(connection)
        except ConnectionAbortedError:
            packet_list = None
        except OSError as e:
            print("OS error:", e)
            packet_list = None
        
        if not packet_list:
            break
        
        for cart_packet in packet_list:
            packet_received_queue.put({
                "sender": cart_packet["subject"],
                "data": cart_packet["data"]
            })
            
    
    print("Host closed the connection.")
    
    packet_received_queue.put({
        "sender": 0,
        "data": bytes([core.SCRIPT_PACKET_REQUEST_DISCONNECT, 0])
    })
    
    if connection is not None:
        connection.close()
        connection = None

def connect_server(ip):
    global connection, packet_received_queue
    packet_received_queue = queue.Queue()
    if connection is not None:
        packet_received_queue.put({
            "sender": 0,
            "data": bytes([core.SCRIPT_PACKET_REQUEST_CONNECT_IP, 1])
        })
        return
    
    print("Connecting to ",ip)
    try:
        connection = socket.create_connection((ip, 5000), timeout=5)
    except socket.timeout:
        print("Connection timed out")
        connection = None
        packet_received_queue.put({
            "sender": 0,
            "data": bytes([core.SCRIPT_PACKET_REQUEST_CONNECT_IP, 0])
        })
        return
    except ConnectionRefusedError:
        print("Connection Refused. LAN might not be hosting anymore.")
        connection = None
        packet_received_queue.put({
            "sender": 0,
            "data": bytes([core.SCRIPT_PACKET_REQUEST_CONNECT_IP, 0])
        })
        return
    
    connection.settimeout(None)
    
    print("Connected.")
    thread = threading.Thread(
        target=connection_handler,
        args=(),
        daemon=True
    )

    thread.start()
    
    packet_received_queue.put({
        "sender": 0,
        "data": bytes([core.SCRIPT_PACKET_REQUEST_CONNECT_IP, 1])
    })

def disconnect_server():
    global connection
    if connection is not None:
        connection.close()
        connection = None


for i in range(256):
    packet_sending_queue[i] = queue.Queue()


def send_packet(receiver, packet):
    packet_sending_queue[receiver].put(packet)


# thread that will send and receive STDIN/STDOUT from the cart
def cart_io(cart):
    while True:
        try:
            packets = get_bytes_and_convert_to_cart_packets(cart.stdout.read)
        except IndexError:
            packets = None

        if packets is None:
            break
        
        # put all the packets the cart sent into packet_sending_queue
        for packet in packets:
            if packet["receiver"]==0:
                # check for commands that are sent to the client script
                command_id = packet["data"][0]
                output = [command_id]
                if command_id == core.SCRIPT_PACKET_REQUEST_CONNECT_IP:
                    # parse ip string from the remaining bytes of the packet
                    ip = ""
                    for idx in range(1,len(packet["data"])):
                        ip += chr(packet["data"][idx])
                    
                    core.attach_thread(connect_server,(ip,)).start()
                    
                    # don't send this local packet to the server
                    continue
                elif command_id == core.SCRIPT_PACKET_REQUEST_DISCONNECT:
                    disconnect_server()
                    
                    # don't send this local packet to the server
                    continue
                
            send_packet(packet["receiver"], {
                "data": packet["data"]
            })
        
        local_packets = []
        
        # get all packets that the cart received
        while len(local_packets)<255:
            try:
                packet = packet_received_queue.get_nowait()
                local_packets.append(packet)
            except queue.Empty:
                break
        
        # write them to the cart
        cart.stdin.write(convert_cart_packets_to_bytes(local_packets))
        cart.stdin.flush()
        
        # send all packets it sent
        if connection is not None:
            connection_messages = []
            
            for cart_id in range(256):
                sending_packets = []
                
                while len(sending_packets)<255:
                    try:
                        packet = packet_sending_queue[cart_id].get_nowait()
                        sending_packets.append({
                            "receiver": cart_id,
                            "data": packet["data"]
                        })
                    except queue.Empty:
                        break
                
                connection_messages += sending_packets
                
            if len(connection_messages)>0:
                try:
                    connection.sendall(core.convert_cart_packets_to_bytes_to_host(connection_messages))
                except OSError:
                    pass
    
def run_cart():
    global cart, cart_thread
    cart = core.create_instance(None, None)

    cart_thread = core.attach_thread(cart_io, (cart,))
    cart_thread.start()











print("Starting client.")

run_cart()


try:
    while True:
        if not cart_thread.is_alive():
            print(f"Thread for cart died. Stopping execution.")
            break
        
        # check for desynchronization
        if packet_state == PACKET_STATE_RECEIVING_DATA:
            # if the cart sent incomplete data, then the function that gets those bytes will halt in the middle of its execution (instead of at the beginning)
            # so counting how long it takes to read an entire packet (if it ever finishes reading one) is a good way to detect desynchronization
            if time.monotonic() - packet_start_time>5:
                print("CRITICAL: Detected packet desync. Terminating PICO-8.")
                if cart.poll() is None:
                    cart.terminate()
                print("Waiting for old cart thread to die...")
                while cart_thread.is_alive():
                    time.sleep(1/10)
                cart = None
                cart_thread = None
                run_cart()
                print("Succesfully restarted PICO-8 to avoid deadlock.")
        
        time.sleep(1/10)
finally:
    if cart.poll() is None:
        cart.terminate()
