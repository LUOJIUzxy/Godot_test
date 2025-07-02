class_name Try
extends CanvasLayer
signal signal1(number: int)

@onready var button:Button = $Control/Button
var connection_attempted: bool = false
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
	print("wallet connected! Account: ", account_address)
	
func on_wallet_error(error_message: String) -> void:
	print("Wallet connection error: ", error_message)
	
		
		
		
	
	
