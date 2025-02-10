import asyncio
import websockets
import json
import os
from PIL import Image
import io
import base64
import hashlib
import uuid  # For generating unique salts
import time  # For temp ban durations
import ssl

connected_clients = {}  # Tracks connected clients with their usernames
player_states = {}  # Tracks the state of each player by their username
mapparts = []  # Track placed parts

FLAGS_FOLDER = "flags"  # Path to the folder containing flag images
# Admins list
admins = ["salih1"]

# Temporary and permanent bans
temp_banned_users = {}  # Temp bans stored in memory (username -> expiry time)
PERMBANS_FILE = "perm_bans.json"  # Permanent ban file

# Hardcoded user table for authentication
user_table = {
    "user1": "password",
    "user2": "password"
}

default_accessories = {
    "no": ["no"]
}

# Load permanent bans from a file
if os.path.exists(PERMBANS_FILE):
    with open(PERMBANS_FILE, "r") as file:
        perm_banned_users = json.load(file)
else:
    perm_banned_users = {}

USERS_FOLDER = "users"  # Folder containing user files

# Create users directory if it doesn't exist
os.makedirs(USERS_FOLDER, exist_ok=True)

async def send_pck_files(username, websocket):
    """Send the name of the .pck file from the mapparts folder to the client."""
    mapparts_folder = "mapparts"
    if os.path.exists(mapparts_folder):
        for file_name in os.listdir(mapparts_folder):
            if file_name.endswith(".pck"):
                # Send just the filename to the client
                await websocket.send(json.dumps({
                    "action": "receive_pck_name",
                    "file_name": file_name
                }))
                print(f"Sent {file_name} to {username}")
                break  # Stop after sending the first .pck file name (remove if you want to send multiple names)

async def handler(websocket):
    username = None

    try:
        async for message in websocket:
            data = json.loads(message)
            action = data.get("action")

            if action == "join":
                username = data.get("username")
                password = data.get("password")
                country = data.get("country", "")
                flag_filename = f"{country if country else username}.TGA"

                if not username or not password:
                    await websocket.send(json.dumps({"action": "auth_failed", "reason": "Missing username or password"}))
                    break
                
                 # Check if the user is permanently banned
                if username in perm_banned_users:
                    await websocket.send(json.dumps({"action": "auth_failed", "reason": f"Perm banned: {perm_banned_users[username]}"}))
                    await websocket.close()  # Disconnect the banned user immediately
                    break

                # Check if the user is temporarily banned
                if username in temp_banned_users and time.time() < temp_banned_users[username]:
                    await websocket.send(json.dumps({"action": "auth_failed", "reason": "Temporarily banned"}))
                    await websocket.close()  # Disconnect the temp banned user
                    break

                if not username or not password:
                    await websocket.send(json.dumps({"action": "auth_failed", "reason": "Missing username or password"}))
                    break

                if authenticate_user(username, password):
                    # Convert the TGA flag to PNG and store the base64-encoded data
                    png_data = await convert_tga_to_png(os.path.join(FLAGS_FOLDER, flag_filename))
                    encoded_flag_data = base64.b64encode(png_data).decode('utf-8') if png_data else ""
                    # Get default accessories for the user, if any
                    accessories = default_accessories.get(username, [])
                    
                    connected_clients[username] = websocket
                    player_states[username] = {
                        "username": username,
                        "country": country,
                        "transform": "default_transform",
                        "rotation": {"x": 0, "y": 0, "z": 0},
                        "InputVector": "(0, 0, 0)",
                        "flag_data": encoded_flag_data,  # Store flag data
                        "emotion": "neutral",  # Default emotion state
                        "accessories": accessories  # Assign default accessories if any
                    }
                    
                    await websocket.send(json.dumps({"action": "auth_success","username": username, "accessories": accessories}))
                    # Send .pck files to the client after successful authentication
                    await send_pck_files(username, websocket)
                    
                    asyncio.create_task(broadcast({
                        "action": "player_joined",
                        "player": player_states[username],
                    }))
                    
                    # Send flags to all players, including the new one
                    asyncio.create_task(send_flag_to_all(username))

                    
                    print(f"Sending {len(mapparts)} parts to {username}")
                    for part in mapparts:
                        try:
                            await websocket.send(json.dumps({
                                "action": "place_part_confirmation",
                                "position": part["position"],
                                "rotation": part["rotation"],
                                "scale": part["scale"],
                                "color": part.get("color", ""),
                                "typepart":  part.get("typepart", ""),
                            }))
                            print(f"Sent part: {part}")
                        except Exception as e:
                            print(f"Failed to send part: {part}, error: {e}")
    
 
                
                else:
                    await websocket.send(json.dumps({"action": "auth_failed", "reason": "Invalid username or password"}))
                    print(f"Authentication failed for username: {username}")  # Log the specific auth failure
                    break
            
            if action == "register":
                username = data.get("username")
                password = data.get("password")
                invite_code = data.get("Invite")

                if not username or not password:
                    await websocket.send(json.dumps({"action": "register_failed", "reason": "Missing username or password"}))
                    break

                # Sanitize username to prevent directory traversal
                if "/" in username or "\\" in username:
                    await websocket.send(json.dumps({"action": "register_failed", "reason": "Invalid username"}))
                    break

                # Check if user already exists
                user_file_path = os.path.join(USERS_FOLDER, f"{username}.json")
                if os.path.exists(user_file_path):
                    await websocket.send(json.dumps({"action": "register_failed", "reason": "Username already taken"}))
                    break

                # Validate invite code
                if not validate_invite_code(invite_code):
                    await websocket.send(json.dumps({"action": "register_failed", "reason": "Invalid invite code"}))
                    break

                try:
                    # Create a new user
                    salt = uuid.uuid4().hex
                    hashed_password = hash_password(password, salt)

                    user_data = {
                        "hashed_password": hashed_password,
                        "salt": salt
                    }

                    # Save the user data to a file
                    with open(user_file_path, "w") as user_file:
                        json.dump(user_data, user_file)

                    await websocket.send(json.dumps({"action": "register_success"}))
                    print(f"User {username} registered successfully.")
                except Exception as e:
                    print(f"Error registering user: {e}")
                    await websocket.send(json.dumps({"action": "register_failed", "reason": "Server error during registration"}))
            
            elif action == "place_part":
                part_data = {
                    "position": data.get("position"),
                    "rotation": data.get("rotation"),
                    "scale": data.get("scale"),
                    "color": data.get("color"),
                    "typepart": data.get("typepart")
                }
                
                if not is_duplicate(part_data):
                    mapparts.append(part_data)
                    await broadcast({
                        "action": "place_part_confirmation",
                        "position": part_data["position"],
                        "rotation": part_data["rotation"],
                        "scale": part_data["scale"],
                        "color": part_data["color"],
                        "typepart": part_data["typepart"]
                    })
                else:
                    pass
            
            elif action == "remove_part":
                position = data.get("position")
                if position:
                    # Find the part with the matching position and remove it
                    part_to_remove = None
                    for part in mapparts:
                        if part["position"] == position:
                            part_to_remove = part
                            break
                    
                    if part_to_remove:
                        mapparts.remove(part_to_remove)
                        await broadcast({
                            "action": "remove_part_confirmation",
                            "position": position
                        })
            
            elif action == "request_all_players":
                await websocket.send(json.dumps({
                    "action": "all_players",
                    "players": list(player_states.values())
                }))

            elif action == "set_hat":
                username = data.get("username")
                hat_name = data.get("hat_name")

                if username in player_states:
                    # Add the hat to the player's accessories list
                    if "accessories" not in player_states[username]:
                        player_states[username]["accessories"] = []
                    
                    # Update the accessories list, ensuring no more than 3 hats
                    if len(player_states[username]["accessories"]) < 3:
                        player_states[username]["accessories"].append(hat_name)
                    else:
                        # Optional: Remove the oldest accessory if there are already 3
                        player_states[username]["accessories"].pop(0)
                        player_states[username]["accessories"].append(hat_name)
                    
                    # Broadcast the updated accessories to all clients, including the local player
                    update_message = {
                        "action": "update_remote_player",
                        "username": username,
                        "transform": player_states[username]["transform"],
                        "rotation": player_states[username]["rotation"],
                        "InputVector": player_states[username]["InputVector"],
                        "emotion": player_states[username]["emotion"],
                        "accessories": player_states[username]["accessories"]
                    }
                    asyncio.create_task(broadcast(update_message))  # This will broadcast to ALL clients

                    print(f"Updated hat for {username}: {player_states[username]['accessories']}")
                else:
                    print(f"Player {username} not found.")



            elif action == "update_player":
                if username in player_states:
                    player_states[username]["transform"] = data.get("transform", player_states[username].get("transform"))
                    player_states[username]["rotation"] = data.get("rotation", player_states[username].get("rotation"))
                    player_states[username]["InputVector"] = data.get("InputVector", player_states[username].get("InputVector"))
                    player_states[username]["emotion"] = data.get("emotion", player_states[username].get("emotion", "neutral"))

                    # Handle accessories update, ensuring no more than 3 are allowed
                    new_accessories = data.get("accessories")
                    if new_accessories is not None:  # Check if accessories field is provided
                        if len(new_accessories) <= 3:
                            player_states[username]["accessories"] = new_accessories
                        else:
                            print(f"Player {username} has too many accessories, limiting to 3")
                    else:
                        # If new_accessories is None, keep the current accessories or set an empty list
                        player_states[username]["accessories"] = player_states[username].get("accessories", [])
                    
                    # Broadcast the updated player state to others
                    update_message = {
                        "action": "update_remote_player",
                        "username": username,
                        "transform": player_states[username]["transform"],
                        "rotation": player_states[username]["rotation"],
                        "InputVector": player_states[username]["InputVector"],
                        "emotion": player_states[username]["emotion"],
                        "accessories": player_states[username]["accessories"]
                    }
                    asyncio.create_task(broadcast_to_others(username, update_message))

            
            elif action == "tohouse":
                response = {"action": "tohouseclient", "username": username, "recieve": "10.0|20.0|30.0"}
                await websocket.send(json.dumps(response))

            elif action == "AccessoryUpdater":
                asyncio.create_task(broadcast_to_others(username, data))

            elif action == "send_chat":
                message = data.get("message")

                # Handle flag change command
                if message.startswith("!flag "):
                    new_flag = message.split()[1]  # Get the flag name after "!flag "
                    
                    # Block username-based flags
                    if new_flag in user_table or new_flag in connected_clients:
                        await websocket.send(json.dumps({
                            "action": "receive_chat",
                            "username": "Server",
                            "message": f"Cannot use username '{new_flag}' as a flag"
                        }))
                        continue  # Use continue instead of return
                    
                    # Convert the TGA flag to PNG and store the base64-encoded data
                    try:
                        flag_filename = f"{new_flag}.TGA"
                        png_data = await convert_tga_to_png(os.path.join(FLAGS_FOLDER, flag_filename))
                        if png_data:
                            encoded_flag_data = base64.b64encode(png_data).decode('utf-8')
                            # Update the player's flag data
                            if username in player_states:
                                player_states[username]["flag_data"] = encoded_flag_data
                                # Broadcast the flag update to all clients
                                await broadcast({
                                    "action": "receive_flag",
                                    "username": username,
                                    "flag_data": encoded_flag_data
                                })
                                await broadcast({
                                    "action": "receive_chat",
                                    "username": username,
                                    "message": f"Changed flag to {new_flag}"
                                })
                                continue  # Use continue instead of return
                        else:
                            await websocket.send(json.dumps({
                                "action": "receive_chat",
                                "username": "Server",
                                "message": f"Flag '{new_flag}' not found"
                            }))
                            continue  # Use continue instead of return
                    except Exception as e:
                        print(f"Error changing flag: {e}")
                        await websocket.send(json.dumps({
                            "action": "receive_chat",
                            "username": "Server",
                            "message": "Error changing flag"
                        }))
                        continue  # Use continue instead of return

                # Handle ban commands from admins
                if username in admins:
                    if message.startswith("!ban "):
                        target_user = message.split()[1]
                        temp_banned_users[target_user] = time.time() + 3600  # 1-hour temp ban
                        # Kick the player if they are currently connected
                        if target_user in connected_clients:
                            await connected_clients[target_user].close()
                            del connected_clients[target_user]  # Remove from connected clients
                        await broadcast({"action": "receive_chat", "username": username, "message": f"{target_user} has been temp banned for 1 hour."})
                        continue

                    elif message.startswith("!permban "):
                        parts = message.split()
                        target_user = parts[1]
                        reason = " ".join(parts[2:]) if len(parts) > 2 else "No reason given"
                        perm_banned_users[target_user] = reason

                        # Save to perm bans file
                        with open(PERMBANS_FILE, "w") as file:
                            json.dump(perm_banned_users, file)

                        # Kick the player if they are currently connected
                        if target_user in connected_clients:
                            await connected_clients[target_user].close()
                            del connected_clients[target_user]  # Remove from connected clients

                        await broadcast({"action": "receive_chat", "username": username, "message": f"{target_user} has been permanently banned. Reason: {reason}"})
                        continue

                # Broadcast the chat message
                broadcast_message = {
                    "action": "receive_chat",
                    "username": username,
                    "message": message
                }
                asyncio.create_task(broadcast(broadcast_message))

            if action == "save_map":
                # Define the path where the map will be saved
                map_name = data.get("map_name")
                initiator = data.get("username")
                save_path = f"{map_name}.json"
                if initiator == "salih1": #TODO
                    # Convert mapparts to JSON format
                    map_data = json.dumps(mapparts, indent=4)
                    
                    # Save the map data to a file
                    with open(save_path, 'w') as file:
                        file.write(map_data)
                    
                    print(f"Map saved to {save_path}")
                    

    except Exception as e:
        print(f"An error occurred: {e}")  # General error logging
    finally:
        if username:
            connected_clients.pop(username, None)
            player_states.pop(username, None)
            asyncio.create_task(broadcast({"action": "player_left", "username": username}))

async def send_flag_to_all(username):
    """Send the stored flag data for all players to the newly joined player."""
    for player_name, state in player_states.items():
        if "flag_data" in state:
            await broadcast({
                "action": "receive_flag",
                "username": player_name,
                "flag_data": state["flag_data"]
            })

def hash_password(password, salt):
    """Hash a password with a given salt using SHA-256."""
    return hashlib.sha256((password + salt).encode()).hexdigest()

def validate_invite_code(invite_code):
    if invite_code == "INV4U":
        return bool(invite_code)
    else:
        return bool(0)

def authenticate_user(username, password):
    """Dynamically check if the provided username and password match the stored hash."""
    user_file_path = os.path.join(USERS_FOLDER, f"{username}.json")
    
    # Check if the user file exists
    if os.path.exists(user_file_path):
        with open(user_file_path, "r") as file:
            user_data = json.load(file)
            salt = user_data["salt"]
            stored_hashed_password = user_data["hashed_password"]
            
            # Hash the input password with the stored salt
            hashed_input_password = hash_password(password, salt)
            
            # Compare the hashed input password with the stored hashed password
            if hashed_input_password == stored_hashed_password:
                return True
    
    # Return False if the user file does not exist or if the passwords do not match
    return False

async def convert_tga_to_png(tga_path):
    """Convert a TGA file to PNG format and return the PNG data."""
    try:
        with Image.open(tga_path) as img:
            # Convert the TGA to PNG in-memory
            with io.BytesIO() as output:
                img.save(output, format="PNG")
                return output.getvalue()
    except Exception as e:
        print(f"Failed to convert {tga_path} to PNG: {e}")
        return None

async def broadcast(message):
    if connected_clients:  # asyncio.wait doesn't accept an empty list
        tasks = [asyncio.create_task(client.send(json.dumps(message))) for client in connected_clients.values()]
        if tasks:
            await asyncio.wait(tasks)

        # Debug information
        print(f"Broadcasting message: {message}")

async def broadcast_to_others(exclude_username, message):
    if connected_clients:
        tasks = [
            asyncio.create_task(client.send(json.dumps(message)))
            for username, client in connected_clients.items()
            if username != exclude_username
        ]
        if tasks:  # Only await if there are tasks to wait on
            await asyncio.wait(tasks)

# Update the is_duplicate function to consider color as well
def is_duplicate(part_data):
    for part in mapparts:
        if (
            part["position"] == part_data["position"] and
            part["rotation"] == part_data["rotation"] and
            part["scale"] == part_data["scale"] and
            part["color"] == part_data["color"] and
            part["typepart"] == part_data["typepart"]
        ):
            return True
    return False

# Load SSL context
ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ssl_context.load_cert_chain(certfile="cert1.crt", keyfile="key1.key")

async def main():
    async with websockets.serve(handler, "0.0.0.0", 8765, ssl=ssl_context):  # Add ssl=ssl_context
        await asyncio.Future()  # run forever

# Load map data from a JSON file when the server starts
if os.path.exists("mapparts.json"):
    with open("mapparts.json", "r") as file:
        mapparts = json.load(file)
    print(f"Loaded {len(mapparts)} parts from mapparts.json")

if __name__ == "__main__":
    asyncio.run(main())
