# This universal script automates the entire process of setting up a worldwide SSH connection
# with ngrok and sending the public URL to a Telegram bot.

import os
import sys
import subprocess
import time
import json
import re

# --- USER CONFIGURATION ---
# IMPORTANT: You will be prompted for these values when you first run the script.
# They will not be saved in this file.
TELEGRAM_BOT_TOKEN = None
TELEGRAM_CHAT_ID = None
NGROK_AUTH_TOKEN = None
# --- END USER CONFIGURATION ---

def check_dependencies():
    """
    Checks if ngrok and the required Python libraries are installed.
    Provides instructions for installation if they are not found, for various Linux distros.
    """
    print("--- Checking Dependencies ---")
    
    # Check for ngrok installation
    try:
        subprocess.run(['which', 'ngrok'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        print("✅ ngrok is installed.")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ ngrok not found. It is required for this script.")
        print("Please install it using one of the following commands, based on your Linux distribution:")
        print("    - Ubuntu/Debian (using snap): sudo snap install ngrok")
        print("    - Fedora/CentOS/RHEL (using dnf): sudo dnf install ngrok")
        print("    - Arch Linux (using pacman): sudo pacman -S ngrok")
        print("    - Generic (from their website): https://ngrok.com/download")
        print("Exiting...")
        sys.exit(1)
        
    # Check for Python's requests library
    try:
        import requests
        print("✅ 'requests' library is installed.")
    except ImportError:
        print("❌ 'requests' library not found. It is required for this script.")
        print("Please install it using the Python package manager 'pip'.")
        print("First, make sure pip is installed on your system:")
        print("    - Ubuntu/Debian: sudo apt-get update && sudo apt-get install python3-pip")
        print("    - Fedora/CentOS/RHEL: sudo dnf install python3-pip")
        print("    - Arch Linux: sudo pacman -S python-pip")
        print("\nThen, install the 'requests' library:")
        print("    pip install requests")
        print("Exiting...")
        sys.exit(1)

def get_credentials():
    """
    Prompts the user for their credentials.
    """
    global TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, NGROK_AUTH_TOKEN
    
    print("\n--- Getting Credentials ---")
    
    # Get ngrok auth token
    ngrok_config_path = os.path.expanduser('~/.config/ngrok/ngrok.yml')
    if os.path.exists(ngrok_config_path):
        print("✅ ngrok auth token is already configured. Skipping.")
    else:
        print("You need to get your ngrok auth token from the ngrok dashboard.")
        NGROK_AUTH_TOKEN = input("Enter your ngrok auth token: ")
        
    print("\nTo get your Telegram Bot Token:")
    print("1. Search for 'BotFather' in Telegram and create a new bot.")
    print("2. Copy the token he gives you.")
    TELEGRAM_BOT_TOKEN = input("Enter your Telegram Bot Token: ")
    
    print("\nTo get your Telegram Chat ID:")
    print("1. Send a message to your new bot (e.g., 'hello').")
    print("2. Go to https://api.telegram.org/botYOUR_BOT_TOKEN/getUpdates (replace YOUR_BOT_TOKEN with your token).")
    print("3. Find your chat ID in the JSON output.")
    TELEGRAM_CHAT_ID = input("Enter your Telegram Chat ID: ")

def configure_ngrok():
    """
    Configures the ngrok auth token.
    """
    if NGROK_AUTH_TOKEN:
        print("\n--- Configuring ngrok ---")
        try:
            subprocess.run(["ngrok", "config", "add-authtoken", NGROK_AUTH_TOKEN], check=True)
            print("✅ ngrok auth token configured successfully.")
        except subprocess.CalledProcessError as e:
            print(f"❌ Failed to configure ngrok auth token. Error: {e}")
            sys.exit(1)

def start_and_send_url():
    """
    Starts the ngrok process, extracts the URL, and sends it to Telegram.
    """
    print("\n--- Starting ngrok and sending URL to Telegram ---")
    
    # The command to start ngrok and expose the SSH port (22)
    ngrok_command = ["ngrok", "tcp", "22", "--log=stdout"]
    
    try:
        process = subprocess.Popen(ngrok_command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        
        start_time = time.time()
        ngrok_url = None
        
        while True:
            line = process.stdout.readline()
            if not line:
                if time.time() - start_time > 15:
                    print("❌ Could not find a URL in ngrok output. Exiting.")
                    break
                time.sleep(1)
                continue
                
            print(f"ngrok log: {line.strip()}")
            
            try:
                log_data = json.loads(line.strip())
                if log_data.get("msg") == "starting tunnel" and "url" in log_data:
                    url = log_data['url']
                    match = re.search(r'tcp://(.+)', url)
                    if match:
                        ngrok_url = match.group(1)
                        print(f"Found ngrok URL: {ngrok_url}")
                        break
            except json.JSONDecodeError:
                continue
        
        if ngrok_url:
            message = f"Your new worldwide SSH connection is ready!\n\nssh tahmid@{ngrok_url}"
            send_telegram_message(message)
        else:
            send_telegram_message("Could not get a new ngrok URL. Something went wrong on the server.")
            
        # Keep the script running to keep ngrok active.
        try:
            while True:
                time.sleep(3600) # Sleep for a long time to keep the script running
        except KeyboardInterrupt:
            print("\nScript terminated by user. ngrok tunnel closed.")

    except FileNotFoundError:
        print("❌ 'ngrok' command not found. Please ensure it is in your PATH.")
        sys.exit(1)

def send_telegram_message(message):
    """
    Sends a message to the specified Telegram chat.
    """
    import requests # Imported here to ensure it's available after the check
    
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    payload = {
        'chat_id': TELEGRAM_CHAT_ID,
        'text': message
    }
    
    try:
        print("Sending message to Telegram...")
        response = requests.post(url, data=payload)
        response.raise_for_status()
        print("✅ Message sent successfully.")
    except requests.exceptions.RequestException as e:
        print(f"❌ Error sending message to Telegram: {e}")
        
if __name__ == "__main__":
    check_dependencies()
    get_credentials()
    configure_ngrok()
    start_and_send_url()
