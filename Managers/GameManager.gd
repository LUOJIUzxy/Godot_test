# GameManager.gd - Enhanced Web3 + Firebase integration
extends Node

@onready var web3_manager = Web3Manager.new()
@onready var ui = $UI

# Game state
var player_level: int = 1
var tokens_earned: int = 0
var session_start_time: int = 0

func _ready():
	# Add Web3 manager to scene
	add_child(web3_manager)
	
	# Connect Web3 signals
	web3_manager.wallet_connected.connect(_on_wallet_connected)
	web3_manager.wallet_error.connect(_on_wallet_error)
	web3_manager.transaction_completed.connect(_on_transaction_completed)
	web3_manager.contract_data_updated.connect(_on_contract_data_updated)
	
	# Connect Database signals
	web3_manager.database_connector.data_retrieved.connect(_on_data_retrieved)
	web3_manager.database_connector.game_stats_saved.connect(_on_game_stats_saved)
	
	# Connect UI signals
	ui.connect_wallet_button.pressed.connect(_on_connect_wallet_pressed)
	ui.switch_to_sepolia_button.pressed.connect(_on_switch_to_sepolia_pressed)
	ui.switch_to_mainnet_button.pressed.connect(_on_switch_to_mainnet_pressed)
	ui.buy_item_button.pressed.connect(_on_buy_item_pressed)
	ui.save_progress_button.pressed.connect(_on_save_progress_pressed)
	
	# Start game session
	session_start_time = Time.get_unix_time_from_system()

func _on_connect_wallet_pressed():
	ui.show_loading("Connecting to wallet...")
	web3_manager.connect_wallet()

func _on_switch_to_sepolia_pressed():
	"""Switch to Sepolia testnet for testing"""
	ui.show_loading("Switching to Sepolia testnet...")
	web3_manager.switch_network(11155111)  # Sepolia chain ID

func _on_switch_to_mainnet_pressed():
	"""Switch to Ethereum mainnet"""
	ui.show_loading("Switching to Ethereum mainnet...")
	web3_manager.switch_network(1)  # Ethereum mainnet chain ID

func _on_wallet_connected(address: String):
	ui.hide_loading()
	ui.show_success("Connected: " + address)
	ui.wallet_address_label.text = address
	
	# Show current network
	var network_name = web3_manager.NETWORKS.get(web3_manager.network_id, {}).get("name", "Unknown")
	ui.network_label.text = "Network: " + network_name
	
	# Load player data from Firebase
	web3_manager.database_connector.get_user_data()
	
	# Load blockchain data
	_load_player_blockchain_data()

func _on_wallet_error(error: String):
	ui.hide_loading()
	ui.show_error("Wallet Error: " + error)

func _load_player_blockchain_data():
	"""Load player's blockchain assets"""
	# Get ETH balance
	web3_manager.get_balance()
	
	# Example: Get game token balance (replace with your contract)
	if web3_manager.network_id == 11155111:  # Sepolia
		# Use Sepolia test contract addresses
		web3_manager.call_contract_view(
			"0x1234567890abcdef1234567890abcdef12345678",  # Your Sepolia token contract
			"balanceOf(address)",
			[web3_manager.wallet_address]
		)
	elif web3_manager.network_id == 1:  # Mainnet
		# Use mainnet contract addresses
		web3_manager.call_contract_view(
			"0xabcdef1234567890abcdef1234567890abcdef12",  # Your mainnet token contract
			"balanceOf(address)",
			[web3_manager.wallet_address]
		)
	
	# Get player's NFTs
	web3_manager.call_contract_view(
		"0x9876543210fedcba9876543210fedcba98765432",  # Your NFT contract
		"balanceOf(address)",
		[web3_manager.wallet_address]
	)

func _on_contract_data_updated(method: String, result: Variant):
	"""Handle blockchain data updates"""
	match method:
		"balance":
			ui.eth_balance_label.text = "ETH: " + str(result)
			
			# Store balance in Firebase for analytics
			web3_manager.database_connector.cache_blockchain_data(
				"eth_balance", 
				{"balance": result, "network_id": web3_manager.network_id}
			)
		
		"balanceOf(address)":
			var balance = int(str(result).hex_to_int()) if typeof(result) == TYPE_STRING else int(result)
			ui.token_balance_label.text = "Tokens: " + str(balance)
			
			# Store token balance
			web3_manager.database_connector.cache_blockchain_data(
				"token_balance",
				{"balance": balance, "network_id": web3_manager.network_id}
			)

func _encode_function_call(function_signature: String, params: Array) -> String:
	"""Helper to encode function calls properly"""
	# Use the same method as in CleanWeb3Manager
	var method_id = web3_manager._get_method_id(function_signature)
	var encoded_params = web3_manager._encode_parameters(params)
	return method_id + encoded_params

func _on_buy_item_pressed():
	"""Buy an item with crypto"""
	var item_price_wei: String
	var game_contract: String
	
	# Different contracts/prices for different networks
	match web3_manager.network_id:
		11155111:  # Sepolia
			item_price_wei = "100000000000000000"  # 0.1 ETH for testing
			game_contract = "0x1111111111111111111111111111111111111111"  # Sepolia contract
		1:  # Mainnet
			item_price_wei = "50000000000000000"   # 0.05 ETH
			game_contract = "0x2222222222222222222222222222222222222222"  # Mainnet contract
		137:  # Polygon
			item_price_wei = "1000000000000000000"  # 1 MATIC
			game_contract = "0x3333333333333333333333333333333333333333"  # Polygon contract
		_:
			ui.show_error("Unsupported network for purchases")
			return
	
	ui.show_loading("Processing purchase...")
	
	# Encode purchase function call properly
	var item_id = 1
	var purchase_data = _encode_function_call("purchaseItem(uint256)", [item_id])
	
	web3_manager.send_transaction(game_contract, item_price_wei, purchase_data)

func _on_transaction_completed(tx_hash: String, success: bool):
	"""Handle transaction completion"""
	ui.hide_loading()
	
	if success:
		ui.show_success("Purchase successful! TX: " + tx_hash)
		
		# Store transaction in Firebase
		web3_manager.database_connector.store_transaction({
			"hash": tx_hash,
			"type": "item_purchase",
			"to_address": "",  # Set appropriate contract address
			"value": "50000000000000000",  # The amount sent
			"status": "confirmed",
			"network_id": web3_manager.network_id
		})
		
		# Update game stats
		tokens_earned += 100  # Reward for purchase
		_update_game_progress()
		
		# Refresh balances
		_load_player_blockchain_data()
	else:
		ui.show_error("Transaction failed")

func _on_save_progress_pressed():
	"""Save current game progress to Firebase"""
	_update_game_progress()
	ui.show_success("Progress saved!")

func _update_game_progress():
	"""Update game statistics in Firebase"""
	var current_time = Time.get_unix_time_from_system()
	var session_duration = current_time - session_start_time
	
	web3_manager.database_connector.update_game_stats({
		"level": player_level,
		"experience": player_level * 1000,  # Example calculation
		"tokens_earned": tokens_earned,
		"total_playtime": session_duration
	})
	
	# Also save session data
	web3_manager.database_connector.save_game_session({
		"start_time": session_start_time,
		"duration": session_duration,
		"score": tokens_earned,
		"level_reached": player_level,
		"blockchain_interactions": 1  # Count of transactions made
	})

func _on_data_retrieved(success: bool, data: Variant):
	"""Handle data retrieved from Firebase"""
	if success and typeof(data) == TYPE_DICTIONARY:
		# Load saved game progress
		var game_stats = data.get("game_stats", {})
		if not game_stats.is_empty():
			player_level = game_stats.get("level", 1)
			tokens_earned = game_stats.get("tokens_earned", 0)
			
			ui.level_label.text = "Level: " + str(player_level)
			ui.tokens_label.text = "Tokens: " + str(tokens_earned)
			
			print("✅ Loaded saved progress: Level ", player_level, ", Tokens: ", tokens_earned)
		
		# Load wallet info
		var wallet_info = data.get("wallet", {})
		if not wallet_info.is_empty():
			print("💾 Previous wallet connection: ", wallet_info.get("wallet_address", ""))
			var last_network = wallet_info.get("network_name", "Unknown")
			ui.last_connection_label.text = "Last connected: " + last_network
		
		# Load transaction history
		var transactions = data.get("transactions", {})
		if not transactions.is_empty():
			_display_transaction_history(transactions)

func _on_game_stats_saved(success: bool):
	"""Handle game stats save confirmation"""
	if success:
		print("✅ Game progress saved to Firebase")
	else:
		push_error("❌ Failed to save game progress")

func _display_transaction_history(transactions: Dictionary):
	"""Display recent transactions in UI"""
	var recent_transactions = []
	
	# Convert dictionary to array and sort by timestamp
	for tx_id in transactions.keys():
		var tx = transactions[tx_id]
		tx["id"] = tx_id
		recent_transactions.append(tx)
	
	# Sort by timestamp (most recent first)
	recent_transactions.sort_custom(func(a, b): return a.get("timestamp", 0) > b.get("timestamp", 0))
	
	# Display last 5 transactions
	var tx_list = ""
	for i in range(min(5, recent_transactions.size())):
		var tx = recent_transactions[i]
		var status_icon = "✅" if tx.get("status") == "confirmed" else "⏳"
		var tx_type = tx.get("type", "unknown").capitalize()
		var network = web3_manager.NETWORKS.get(tx.get("network_id", 0), {}).get("name", "Unknown")
		
		tx_list += status_icon + " " + tx_type + " on " + network + "\n"
	
	ui.transaction_history_label.text = tx_list

# Game progression functions
func _on_level_up():
	"""Handle player leveling up"""
	player_level += 1
	tokens_earned += 50  # Bonus tokens for leveling up
	
	ui.level_label.text = "Level: " + str(player_level)
	ui.tokens_label.text = "Tokens: " + str(tokens_earned)
	
	# Save progress immediately on level up
	_update_game_progress()
	
	ui.show_success("Level up! You're now level " + str(player_level))

func _on_collect_nft_reward():
	"""Handle NFT collection/minting"""
	if not web3_manager.is_wallet_connected:
		ui.show_error("Connect wallet to collect NFT")
		return
	
	# Example NFT minting transaction
	var nft_contract = ""
	var mint_price = "0"  # Free mint example
	
	match web3_manager.network_id:
		11155111:  # Sepolia
			nft_contract = "0x4444444444444444444444444444444444444444"  # Sepolia NFT contract
		1:  # Mainnet
			nft_contract = "0x5555555555555555555555555555555555555555"  # Mainnet NFT contract
			mint_price = "10000000000000000"  # 0.01 ETH on mainnet
		_:
			ui.show_error("NFT minting not available on this network")
			return
	
	ui.show_loading("Minting NFT...")
	
	# Encode mint function call properly
	var mint_data = _encode_function_call("mint(address)", [web3_manager.wallet_address])
	
	web3_manager.send_transaction(nft_contract, mint_price, mint_data)

func _on_nft_minted_successfully(tx_hash: String):
	"""Handle successful NFT minting"""
	# Store NFT data in Firebase
	web3_manager.database_connector.store_nft_data({
		"token_id": "1",  # You'd get this from the transaction receipt
		"contract_address": "0x4444444444444444444444444444444444444444",
		"name": "Game Achievement NFT",
		"description": "Earned by reaching level " + str(player_level),
		"image_url": "https://your-game.com/nft-images/achievement.png",
		"attributes": [
			{"trait_type": "Level", "value": player_level},
			{"trait_type": "Tokens Earned", "value": tokens_earned},
			{"trait_type": "Network", "value": web3_manager.network_id}
		],
		"network_id": web3_manager.network_id
	})

# Network switching helpers
func _setup_network_buttons():
	"""Setup network switching UI"""
	ui.sepolia_button.text = "Sepolia (Test)"
	ui.mainnet_button.text = "Ethereum"
	ui.polygon_button.text = "Polygon"
	
	# Enable/disable based on current network
	match web3_manager.network_id:
		11155111:
			ui.sepolia_button.disabled = true
			ui.mainnet_button.disabled = false
			ui.polygon_button.disabled = false
		1:
			ui.sepolia_button.disabled = false
			ui.mainnet_button.disabled = true
			ui.polygon_button.disabled = false
		137:
			ui.sepolia_button.disabled = false
			ui.mainnet_button.disabled = false
			ui.polygon_button.disabled = true

func _on_polygon_switch_pressed():
	"""Switch to Polygon network"""
	ui.show_loading("Switching to Polygon...")
	web3_manager.switch_network(137)

# Analytics and metrics
func _track_user_engagement():
	"""Track user engagement metrics"""
	var engagement_data = {
		"session_length": Time.get_unix_time_from_system() - session_start_time,
		"wallet_connected": web3_manager.is_wallet_connected,
		"network_used": web3_manager.network_id,
		"transactions_made": 0,  # Track this throughout the session
		"level_achieved": player_level,
		"nfts_collected": 0  # Track NFT collections
	}
	
	# Store engagement metrics
	web3_manager.database_connector._make_firebase_request(
		"analytics/user_engagement/" + web3_manager.database_connector.get_user_id() + ".json",
		HTTPClient.METHOD_PATCH,
		engagement_data,
		web3_manager.database_connector.RequestType.UPDATE_GAME_STATS
	)

# Error handling and recovery
func _handle_network_error():
	"""Handle network connectivity issues"""
	ui.show_error("Network connection issue. Retrying...")
	
	# Retry connection after delay
	await get_tree().create_timer(3.0).timeout
	
	if web3_manager.is_wallet_connected:
		_load_player_blockchain_data()

func _handle_transaction_failure(error_message: String):
	"""Handle transaction failures with user-friendly messages"""
	var user_message = ""
	
	if "insufficient funds" in error_message.to_lower():
		user_message = "Insufficient funds. Please add more ETH to your wallet."
	elif "user rejected" in error_message.to_lower():
		user_message = "Transaction was cancelled."
	elif "gas" in error_message.to_lower():
		user_message = "Transaction failed due to gas issues. Try again with higher gas."
	else:
		user_message = "Transaction failed: " + error_message
	
	ui.show_error(user_message)

# Cleanup and session management
func _exit_tree():
	"""Save progress when exiting game"""
	if web3_manager.is_wallet_connected:
		_update_game_progress()
		_track_user_engagement()

func _notification(what):
	"""Handle system notifications"""
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Save progress before closing
		_update_game_progress()
		_track_user_engagement()
		get_tree().quit()
