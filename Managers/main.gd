# Main.gd - Your main scene script
extends Control

# UI References - using get_node() instead of @onready
@onready var test_firebase_button: Button = $Main/VBoxContainer/TestFirebaseButton
@onready var connect_wallet_button: Button = $Main/VBoxContainer/ConnectWalletButton
@onready var send_transaction_button: Button = $Main/VBoxContainer/SendTransactionButton
@onready var status_label: Label = $Main/VBoxContainer/StatusLabel
@onready var wallet_info_label: Label = $Main/VBoxContainer/WalletInfoLabel


# Web3 Manager
var web3_manager = Web3_Manager

func _ready():
	setup_ui()
	setup_web3_and_firebase()

func setup_ui():
	"""Setup UI elements and connect signals"""
	# Get node references
	test_firebase_button = $VBoxContainer/TestFirebaseButton
	connect_wallet_button = $VBoxContainer/ConnectWalletButton
	send_transaction_button = $VBoxContainer/SendTransactionButton
	status_label = $VBoxContainer/StatusLabel
	wallet_info_label = $VBoxContainer/WalletInfoLabel
	
	# Check if nodes exist before connecting
	if test_firebase_button == null:
		push_error("TestFirebaseButton not found! Check node name and path.")
		return
	if connect_wallet_button == null:
		push_error("ConnectWalletButton not found! Check node name and path.")
		return
	if send_transaction_button == null:
		push_error("SendTransactionButton not found! Check node name and path.")
		return
	if status_label == null:
		push_error("StatusLabel not found! Check node name and path.")
		return
	if wallet_info_label == null:
		push_error("WalletInfoLabel not found! Check node name and path.")
		return
	
	# Connect button signals
	test_firebase_button.pressed.connect(_on_test_firebase_pressed)
	connect_wallet_button.pressed.connect(_on_connect_wallet_pressed)
	send_transaction_button.pressed.connect(_on_send_transaction_pressed)
	
	# Initial button states
	send_transaction_button.disabled = true  # Disabled until wallet connected
	
	# Initial status
	status_label.text = "Ready - Click 'Test Firebase' to verify connection"
	wallet_info_label.text = "Wallet: Not connected"

func setup_web3_and_firebase():
	"""Initialize Web3 manager with Firebase"""
	#web3_manager = Web3Manager.new()
	#add_child(web3_manager)
	
	# Connect Web3 signals
	web3_manager.wallet_connected.connect(_on_wallet_connected)
	web3_manager.wallet_error.connect(_on_wallet_error)
	web3_manager.transaction_completed.connect(_on_transaction_completed)
	web3_manager.contract_data_updated.connect(_on_contract_data_updated)
	
	# Connect Firebase signals
	web3_manager.database_connector.data_stored.connect(_on_firebase_data_stored)
	web3_manager.database_connector.data_retrieved.connect(_on_firebase_data_retrieved)
	
	print("🎮 Web3 + Firebase initialized!")

# === BUTTON HANDLERS ===

func _on_test_firebase_pressed():
	"""Test Firebase connection"""
	status_label.text = "🔥 Testing Firebase connection..."
	test_firebase_button.disabled = true
	
	print("🧪 Testing Firebase...")
	
	# Test storing data
	var test_data = {
		"test_message": "Hello from Godot Web3 Game!",
		"timestamp": Time.get_unix_time_from_system(),
		"version": "1.0",
		"platform": "web"
	}
	
	web3_manager.database_connector.store_user_wallet({
		"address": "0x1234567890abcdef1234567890abcdef12345678",
		"network_id": 11155111,
		"network_name": "Sepolia Testnet",
		"connected_at": Time.get_unix_time_from_system()
	})

func _on_connect_wallet_pressed():
	"""Connect to Web3 wallet"""
	status_label.text = "🔗 Connecting to wallet..."
	connect_wallet_button.disabled = true
	
	print("🔗 Connecting wallet...")
	web3_manager.connect_wallet()

func _on_send_transaction_pressed():
	"""Send a test transaction"""
	if not web3_manager.is_wallet_connected:
		status_label.text = "❌ Please connect wallet first"
		return
	
	status_label.text = "📤 Sending test transaction..."
	send_transaction_button.disabled = true
	
	# Send a small test transaction based on network
	var recipient = web3_manager.wallet_address  # Send to self for testing
	var amount_wei = "1000000000000000"  # 0.001 ETH
	
	match web3_manager.network_id:
		11155111:  # Sepolia
			status_label.text = "📤 Sending 0.001 ETH on Sepolia testnet..."
		1:  # Mainnet  
			status_label.text = "📤 Sending 0.001 ETH on Ethereum mainnet..."
		137:  # Polygon
			status_label.text = "📤 Sending 0.001 MATIC on Polygon..."
		_:
			status_label.text = "❌ Unsupported network for test transaction"
			send_transaction_button.disabled = false
			return
	
	print("📤 Sending test transaction...")
	web3_manager.send_transaction(recipient, amount_wei)

# === WEB3 EVENT HANDLERS ===

func _on_wallet_connected(address: String):
	"""Handle wallet connection success"""
	status_label.text = "✅ Wallet connected successfully!"
	wallet_info_label.text = "Wallet: " + address.substr(0, 6) + "..." + address.substr(-4)
	
	var network_name = web3_manager.NETWORKS.get(web3_manager.network_id, {}).get("name", "Unknown")
	wallet_info_label.text += " (" + network_name + ")"
	
	# Enable transaction button
	send_transaction_button.disabled = false
	connect_wallet_button.disabled = false
	connect_wallet_button.text = "Reconnect Wallet"
	
	print("🎉 Wallet connected: ", address)
	
	# Load wallet balance
	web3_manager.get_balance()

func _on_wallet_error(error: String):
	"""Handle wallet connection error"""
	status_label.text = "❌ Wallet error: " + error
	connect_wallet_button.disabled = false
	
	print("❌ Wallet error: ", error)

func _on_transaction_completed(tx_hash: String, success: bool):
	"""Handle transaction completion"""
	send_transaction_button.disabled = false
	
	if success:
		status_label.text = "✅ Transaction successful! Hash: " + tx_hash.substr(0, 10) + "..."
		print("✅ Transaction successful: ", tx_hash)
		
		# Store transaction in Firebase
		web3_manager.database_connector.store_transaction({
			"hash": tx_hash,
			"type": "test_transaction",
			"to_address": web3_manager.wallet_address,
			"value": "1000000000000000",
			"status": "confirmed",
			"network_id": web3_manager.network_id
		})
	else:
		status_label.text = "❌ Transaction failed"
		print("❌ Transaction failed")

func _on_contract_data_updated(method: String, result: Variant):
	"""Handle blockchain data updates"""
	match method:
		"balance":
			var balance_text = "Balance: " + str(result).pad_decimals(4) + " ETH"
			wallet_info_label.text = wallet_info_label.text.split(" (")[0] + " | " + balance_text
			print("💰 Balance updated: ", result, " ETH")

# === FIREBASE EVENT HANDLERS ===

func _on_firebase_data_stored(success: bool, response: Dictionary):
	"""Handle Firebase data storage result"""
	test_firebase_button.disabled = false
	
	if success:
		status_label.text = "✅ Firebase test successful! Data stored."
		print("✅ Firebase storage successful")
		
		# Test reading the data back
		web3_manager.database_connector.get_user_data()
	else:
		status_label.text = "❌ Firebase test failed - check configuration"
		print("❌ Firebase storage failed")

func _on_firebase_data_retrieved(success: bool, data: Variant):
	"""Handle Firebase data retrieval result"""
	if success:
		status_label.text = "✅ Firebase fully working! Read/Write successful."
		print("✅ Firebase data retrieved: ", data)
	else:
		status_label.text = "❌ Firebase read failed"
		print("❌ Firebase data retrieval failed")

# === UTILITY FUNCTIONS ===

func show_loading(message: String):
	"""Show loading state"""
	status_label.text = message
	
func show_success(message: String):
	"""Show success message"""
	status_label.text = "✅ " + message
	
func show_error(message: String):
	"""Show error message"""
	status_label.text = "❌ " + message
