class_name Try
extends CanvasLayer
signal signal1(number: int)

@onready var button:Button = $Control/Button
var connection_attempted: bool = false
var sepolia_switch_attempted: bool = false
#var callback_timer: Timer

func _ready() -> void:
	button.pressed.connect(_on_Button_press)
	signal1.connect(_print_signal)
	
	#callback_timer = Timer.new()
	#callback_timer.wait_time = 0.1 # check every 100ms
	#callback_timer.timeout.connect(_check_wallet_callback)
	#add_child(callback_timer)
	
	
func _on_Button_press() -> void:
	print('Attempting to connect to Ethereum wallet and check for Sepolia testnet...')
	signal1.emit(2)
	
	if connection_attempted:
		print("Connection already attempted. Please refresh the page to try again.")
		return
		
	connection_attempted = true
	sepolia_switch_attempted = false
	
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""
			window.wallet_status = 'connecting';
			window.wallet_account = null;
			window.wallet_error = null;
		""")
		
		JavaScriptBridge.eval("globalThis.connectWalletBasic('simple_callback')")
		
		JavaScriptBridge.eval("""
			window.simple_callback = function (result) {
				console.log('Simple callback called with:', result);
				try {
					if (result.includes('success":true')) {
						window.wallet_status = 'connected';
						var accountMatch = result.match('"account":"([^"]+)"');
						if (accountMatch) {
							window.wallet_account = accountMatch[1];
						}
					} else {
						window.wallet_status = 'error';
						var errorMatch = result.match('"error":"([^"]+)"');
						if (errorMatch) {
							window.wallet_error = errorMatch[1];
						}
					}
					
				} catch(e) {
					console.error('Callback error: ', e);
					window.wallet_status = 'error';
					window.wallet_error = 'Callback failed!'
					
				}
			}
		""")
		
		print("Wallet connection initiated, waiting for response....")
		
		await get_tree().create_timer(2.0).timeout
		check_wallet_result()
		
	else:
		print("This Ethereum wallet connection feature is only available in HTML5 export with Javascript bridging")
		
func _print_signal(number: int) -> void:
	print(number)
	
func check_wallet_result():
	if not OS.has_feature("web"):
		return
		
	var status = JavaScriptBridge.eval("window.wallet_status")
	print("Wallet status: ", status)
	
	if status == "connected":
		var account = JavaScriptBridge.eval("window.wallet_account")
		on_wallet_connected(str(account))
	elif status == "error":
		var error = JavaScriptBridge.eval("window.wallet_error")
		on_wallet_error(str(error))
	else:
		print("Still connecting... checking again in 1 second")
		await get_tree().create_timer(1.0).timeout
		check_wallet_result()
		
		
func on_wallet_connected(account_address: String) -> void:
	print("✅ Wallet connected! Account: ", account_address)
	print("🔄 Automatically switching to Sepolia testnet...")
	
	# Automatically switch to Sepolia testnet
	if not sepolia_switch_attempted:
		sepolia_switch_attempted = true
		switch_to_sepolia()
	
func switch_to_sepolia() -> void:
	if not OS.has_feature("web"):
		print("Sepolia switch only available in web export")
		return
		
	# Set up Sepolia switch status tracking
	JavaScriptBridge.eval("""
		window.sepolia_status = 'switching';
		window.sepolia_message = null;
		window.sepolia_error = null;
	""")
	
	# Call the switchToSepolia function
	JavaScriptBridge.eval("globalThis.switchToSepolia('sepolia_callback')")
	
	# Set up the callback for Sepolia switch
	JavaScriptBridge.eval("""
		window.sepolia_callback = function (result) {
			console.log('Sepolia callback called with:', result);
			try {
				if (result.includes('success":true')) {
					window.sepolia_status = 'switched';
					var messageMatch = result.match('"message":"([^"]+)"');
					if (messageMatch) {
						window.sepolia_message = messageMatch[1];
					}
				} else {
					window.sepolia_status = 'error';
					var errorMatch = result.match('"error":"([^"]+)"');
					if (errorMatch) {
						window.sepolia_error = errorMatch[1];
					}
				}
			} catch(e) {
				console.error('Sepolia callback error: ', e);
				window.sepolia_status = 'error';
				window.sepolia_error = 'Sepolia callback failed!'
			}
		}
	""")
	
	print("Sepolia switch initiated, waiting for response...")
	
	await get_tree().create_timer(2.0).timeout
	check_sepolia_result()

func check_sepolia_result():
	if not OS.has_feature("web"):
		return
		
	var status = JavaScriptBridge.eval("window.sepolia_status")
	print("Sepolia switch status: ", status)
	
	if status == "switched":
		var message = JavaScriptBridge.eval("window.sepolia_message")
		on_sepolia_switched(str(message))
	elif status == "error":
		var error = JavaScriptBridge.eval("window.sepolia_error")
		on_sepolia_error(str(error))
	else:
		print("Still switching to Sepolia... checking again in 1 second")
		await get_tree().create_timer(1.0).timeout
		check_sepolia_result()

func on_sepolia_switched(message: String) -> void:
	print("✅ Successfully switched to Sepolia testnet! ", message)
	print("🎉 Wallet setup complete - connected to Sepolia testnet")

func on_sepolia_error(error_message: String) -> void:
	print("❌ Sepolia switch error: ", error_message)
	print("⚠️  Wallet connected but network switch failed")
	
func on_wallet_error(error_message: String) -> void:
	print("❌ Wallet connection error: ", error_message) 