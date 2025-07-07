# CleanWeb3Manager.gd - Streamlined Web3 integration
class_name Web3Manager
extends Node

signal wallet_connected(address: String)
signal transaction_completed(tx_hash: String, success: bool)
signal contract_data_updated(method: String, result: Variant)
signal wallet_error(error: String)

# Configuration
#const ETHEREUM_RPC = "https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY"
#const POLYGON_RPC = "https://polygon-mainnet.g.alchemy.com/v2/YOUR_API_KEY"
const SEPOLIA_RPC = "https://eth-sepolia.api.onfinality.io/public"
const CACHE_DURATION = 30.0

# Network configuration
const NETWORKS = {
	#1: {"name": "Ethereum Mainnet", "rpc": ETHEREUM_RPC},
	#137: {"name": "Polygon", "rpc": POLYGON_RPC},
	11155111: {"name": "Sepolia Testnet", "rpc": SEPOLIA_RPC}
}

# State
var wallet_address: String = ""
var is_wallet_connected: bool = false
var network_id: int = 1
var cached_data: Dictionary = {}
var cache_timestamps: Dictionary = {}

# Nodes
var http_request: HTTPRequest
var database_connector = Firebase_Connector

func _ready():
	_setup_http_client()
	_setup_minimal_web3_bridge()

func _setup_http_client():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_http_request_completed)


func _setup_minimal_web3_bridge():
	"""Setup minimal JavaScript bridge - only what's absolutely necessary"""
	
	if not OS.has_feature("web"):
		push_warning("Web3Manager: Not running in web environment")
		return
	
	# Only inject the bare minimum JavaScript needed for wallet interaction
	var minimal_web3_setup = """
	// Minimal Web3 setup - just the essentials
	(function() {
		if (window.godotWeb3Ready) return;
		
		// Load Web3.js if needed
		if (typeof Web3 === 'undefined') {
			const script = document.createElement('script');
			script.src = 'https://cdnjs.cloudflare.com/ajax/libs/web3/4.2.2/web3.min.js';
			script.onload = () => { 
				window.godotWeb3Ready = true;
				console.log('Web3.js ready for Godot');
			};
			document.head.appendChild(script);
		} else {
			window.godotWeb3Ready = true;
		}
		
		// Simple callback system
		window.godotCallbacks = {};
	})();
	"""
	
	JavaScriptBridge.eval(minimal_web3_setup)
	
	# Wait for Web3.js, then setup callbacks
	await get_tree().create_timer(1.0).timeout
	_setup_callbacks()

func _setup_callbacks():
	"""Setup minimal callback system"""
	var callback_methods = [
		"_on_wallet_connected",
		"_on_wallet_error", 
		"_on_transaction_sent",
		"_on_transaction_error"
	]
	
	for method in callback_methods:
		var js_assignment = "window.godotCallbacks.%s = %s" % [
			method.substr(1), # Remove the leading underscore
			JavaScriptBridge.create_callback(get(method))
		]
		JavaScriptBridge.eval(js_assignment)

# === PUBLIC API - These are the ONLY functions you need to call ===

func connect_wallet():
	"""Connect to Web3 wallet - Main entry point"""
	if not OS.has_feature("web"):
		emit_signal("wallet_error", "Not running in web environment")
		return
	
	# Execute wallet connection directly in this function
	var connect_js = """
	(async function() {
		try {
			// Check for provider
			if (typeof window.ethereum === 'undefined') {
				throw new Error('No Web3 wallet found. Please install MetaMask.');
			}
			
			// Request accounts
			const accounts = await window.ethereum.request({
				method: 'eth_requestAccounts'
			});
			
			if (accounts.length === 0) {
				throw new Error('No accounts found. Please unlock your wallet.');
			}
			
			// Get network
			const web3 = new Web3(window.ethereum);
			const chainId = await web3.eth.getChainId();
			
			// Setup account/network change listeners
			window.ethereum.on('accountsChanged', (accounts) => {
				if (accounts.length > 0) {
					window.godotCallbacks.wallet_connected(accounts[0], chainId);
				} else {
					window.godotCallbacks.wallet_error('Wallet disconnected');
				}
			});
			
			window.ethereum.on('chainChanged', (chainId) => {
				window.godotCallbacks.wallet_connected(accounts[0], parseInt(chainId, 16));
			});
			
			// Success callback
			window.godotCallbacks.wallet_connected(accounts[0], chainId);
			
		} catch (error) {
			window.godotCallbacks.wallet_error(error.message);
		}
	})();
	"""
	
	JavaScriptBridge.eval(connect_js)

func send_transaction(to_address: String, value: String, data: String = "0x"):
	"""Send transaction - Main entry point"""
	if not is_wallet_connected:
		emit_signal("wallet_error", "Wallet not connected")
		return
	
	var transaction_js = """
	(async function() {
		try {
			const web3 = new Web3(window.ethereum);
			
			const txParams = {
				to: '%s',
				from: '%s',
				value: web3.utils.toHex('%s'),
				data: '%s'
			};
			
			// Estimate gas
			const gasEstimate = await web3.eth.estimateGas(txParams);
			txParams.gas = web3.utils.toHex(gasEstimate);
			
			// Send transaction
			const txHash = await window.ethereum.request({
				method: 'eth_sendTransaction',
				params: [txParams]
			});
			
			window.godotCallbacks.transaction_sent(txHash);
			
		} catch (error) {
			window.godotCallbacks.transaction_error(error.message);
		}
	})();
	""" % [to_address, wallet_address, value, data]
	
	JavaScriptBridge.eval(transaction_js)

func sign_message(message: String):
	"""Sign message with wallet"""
	if not is_wallet_connected:
		emit_signal("wallet_error", "Wallet not connected")
		return
	
	var sign_js = """
	(async function() {
		try {
			const web3 = new Web3(window.ethereum);
			const signature = await web3.eth.personal.sign('%s', '%s');
			window.godotCallbacks.message_signed(signature);
		} catch (error) {
			window.godotCallbacks.wallet_error('Signing failed: ' + error.message);
		}
	})();
	""" % [message, wallet_address]
	
	JavaScriptBridge.eval(sign_js)

func switch_network(chain_id: int):
	"""Switch to different network"""
	if not NETWORKS.has(chain_id):
		emit_signal("wallet_error", "Unsupported network: " + str(chain_id))
		return
	
	var switch_js = """
	(async function() {
		try {
			await window.ethereum.request({
				method: 'wallet_switchEthereumChain',
				params: [{ chainId: '0x%s' }]
			});
		} catch (switchError) {
			// Network might not be added to wallet, try adding it
			if (switchError.code === 4902) {
				try {
					await window.ethereum.request({
						method: 'wallet_addEthereumChain',
						params: [{
							chainId: '0x%s',
							chainName: '%s',
							rpcUrls: ['%s']
						}]
					});
				} catch (addError) {
					window.godotCallbacks.wallet_error('Failed to add network: ' + addError.message);
				}
			} else {
				window.godotCallbacks.wallet_error('Network switch failed: ' + switchError.message);
			}
		}
	})();
	""" % [
		String.num_int64(chain_id, 16),
		String.num_int64(chain_id, 16), 
		NETWORKS[chain_id].name,
		NETWORKS[chain_id].rpc
	]
	
	JavaScriptBridge.eval(switch_js)

# === BLOCKCHAIN READING (HTTP-based for performance) ===

func get_balance(address: String = ""):
	"""Get ETH balance via RPC (cached)"""
	var target_address = address if address != "" else wallet_address
	if target_address == "":
		emit_signal("wallet_error", "No address provided")
		return
	
	var cache_key = "balance_" + target_address
	if _is_cached_valid(cache_key):
		emit_signal("contract_data_updated", "balance", cached_data[cache_key])
		return
	
	_make_rpc_call("eth_getBalance", [target_address, "latest"], "balance", cache_key)

func call_contract_view(contract_address: String, method_signature: String, params: Array = []):
	"""Call read-only contract method (cached)"""
	var cache_key = "contract_%s_%s" % [contract_address, method_signature]
	
	if _is_cached_valid(cache_key):
		emit_signal("contract_data_updated", method_signature, cached_data[cache_key])
		return
	
	var method_id = _get_method_id(method_signature)
	var encoded_params = _encode_parameters(params)
	var call_data = method_id + encoded_params
	
	_make_rpc_call("eth_call", [{
		"to": contract_address,
		"data": call_data
	}, "latest"], method_signature, cache_key)

func get_transaction_receipt(tx_hash: String):
	"""Check transaction status"""
	_make_rpc_call("eth_getTransactionReceipt", [tx_hash], "tx_receipt")

# === CALLBACKS (only called by JavaScript) ===

func _on_wallet_connected(args):
	wallet_address = args[0]
	network_id = int(args[1])
	is_wallet_connected = true
	
	print("✅ Wallet connected: ", wallet_address, " on ", NETWORKS.get(network_id, {}).get("name", "Unknown Network"))
	
	# Store in Firebase
	database_connector.store_user_wallet({
		"address": wallet_address,
		"network_id": network_id,
		"network_name": NETWORKS.get(network_id, {}).get("name", "Unknown"),
		"connected_at": Time.get_unix_time_from_system()
	})
	
	emit_signal("wallet_connected", wallet_address)

func _on_wallet_error(args):
	var error_msg = args[0] if args.size() > 0 else "Unknown error"
	print("❌ Wallet error: ", error_msg)
	emit_signal("wallet_error", error_msg)

func _on_transaction_sent(args):
	var tx_hash = args[0]
	print("📤 Transaction sent: ", tx_hash)
	_monitor_transaction(tx_hash)

func _on_transaction_error(args):
	var error_msg = args[0] if args.size() > 0 else "Transaction failed"
	print("❌ Transaction error: ", error_msg)
	emit_signal("transaction_completed", "", false)

# === HTTP RPC HANDLING ===

func _make_rpc_call(method: String, params: Array, callback_type: String, cache_key: String = ""):
	var current_network = NETWORKS.get(network_id, {})
	if current_network.is_empty():
		push_error("Unsupported network ID: " + str(network_id))
		return
	
	var rpc_url = current_network.rpc
	
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({
		"jsonrpc": "2.0",
		"method": method,
		"params": params,
		"id": randi()
	})
	
	http_request.set_meta("callback_type", callback_type)
	http_request.set_meta("cache_key", cache_key)
	
	http_request.request(rpc_url, headers, HTTPClient.METHOD_POST, body)

func _on_http_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code != 200:
		push_error("RPC failed: " + str(response_code))
		return
	
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		push_error("Invalid JSON response")
		return
	
	var response = json.data
	var callback_type = http_request.get_meta("callback_type", "")
	var cache_key = http_request.get_meta("cache_key", "")
	
	if response.has("error"):
		push_error("RPC Error: " + str(response.error))
		return
	
	var result_data = response.result
	
	# Cache if requested
	if cache_key != "":
		cached_data[cache_key] = result_data
		cache_timestamps[cache_key] = Time.get_time_dict_from_system()
	
	# Handle specific response types
	match callback_type:
		"balance":
			var balance_eth = _wei_to_eth(result_data)
			emit_signal("contract_data_updated", "balance", balance_eth)
		
		"tx_receipt":
			var success = result_data != null and result_data.get("status", "0x0") == "0x1"
			var tx_hash = result_data.get("transactionHash", "") if result_data else ""
			emit_signal("transaction_completed", tx_hash, success)
		
		_:
			emit_signal("contract_data_updated", callback_type, result_data)

# === UTILITY FUNCTIONS ===

func _monitor_transaction(tx_hash: String):
	"""Monitor transaction until confirmed"""
	for i in range(20):  # Max 20 attempts
		await get_tree().create_timer(3.0).timeout
		get_transaction_receipt(tx_hash)

func _is_cached_valid(cache_key: String) -> bool:
	if not cached_data.has(cache_key):
		return false
	
	var cached_time = cache_timestamps.get(cache_key, {})
	var current_time = Time.get_time_dict_from_system()
	var time_diff = current_time.get("unix", 0) - cached_time.get("unix", 0)
	
	return time_diff < CACHE_DURATION

func _wei_to_eth(wei_string: String) -> float:
	if wei_string.begins_with("0x"):
		var wei_int = wei_string.hex_to_int()
		return float(wei_int) / 1000000000000000000.0
	return 0.0

func _get_method_id(signature: String) -> String:
	# Common method signatures - add more as needed
	var method_ids = {
		"balanceOf(address)": "0x70a08231",
		"transfer(address,uint256)": "0xa9059cbb", 
		"totalSupply()": "0x18160ddd",
		"approve(address,uint256)": "0x095ea7b3",
		"purchaseItem(uint256)": "0xa1b2c3d4",  # Replace with real method ID
		"mint(address)": "0x6a627842"  # Replace with real method ID
	}
	return method_ids.get(signature, "0x00000000")

func _encode_parameters(params: Array) -> String:
	# Simple ABI encoding - extend as needed
	var encoded = ""
	for param in params:
		if param is String and param.begins_with("0x"):
			# Address
			encoded += param.substr(2).pad_zeros(64)
		elif param is int:
			# Integer
			encoded += String.num_int64(param, 16).pad_zeros(64)
	return encoded
