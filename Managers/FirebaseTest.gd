# FirebaseTest.gd - Test Firebase connection
extends Node

func _ready():
	test_firebase_connection()

func test_firebase_connection():
	print("🔥 Testing Firebase connection...")
	
	# Create database connector
	var db = FirebaseConnector.new()
	add_child(db)
	
	# Connect signals
	db.data_stored.connect(_on_data_stored)
	db.data_retrieved.connect(_on_data_retrieved)
	
	# Test storing data
	var test_data = {
		"test_message": "Hello Firebase!",
		"timestamp": Time.get_unix_time_from_system(),
		"from": "Godot Web3 Game"
	}
	
	print("📤 Storing test data...")
	db._make_firebase_request(
		"test/connection.json",
		HTTPClient.METHOD_PUT,
		test_data,
		db.RequestType.STORE_USER_WALLET
	)

func _on_data_stored(success: bool, response: Dictionary):
	if success:
		print("✅ Firebase WRITE test successful!")
		print("📥 Now testing READ...")
		
		# Test reading data back
		var db = get_child(0) as FirebaseConnector
		db._make_firebase_request(
			"test/connection.json",
			HTTPClient.METHOD_GET,
			{},
			db.RequestType.GET_USER_DATA
		)
	else:
		print("❌ Firebase WRITE test failed!")
		print("Check your Firebase configuration and network connection")

func _on_data_retrieved(success: bool, data: Variant):
	if success:
		print("✅ Firebase READ test successful!")
		print("📄 Retrieved data: ", data)
		print("🎉 Firebase is working correctly!")
	else:
		print("❌ Firebase READ test failed!")
		print("Check your Firebase security rules and configuration")
