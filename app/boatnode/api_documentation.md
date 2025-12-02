# API Documentation (Mock)

## Base URL
`https://mock-api.boatnode.com/v1`

## Endpoints

### Authentication & Profile

#### `POST /auth/login`
- **Input**: `{ "phone": "+919876543210", "otp": "123456" }`
- **Output**: `{ "token": "jwt...", "user": { ... } }`

#### `POST /profile/update`
- **Input**: `{ "display_name": "Raja", "role": "owner", "village_id": "uuid..." }`
- **Output**: `{ "success": true, "user": { ... } }`

#### `GET /villages`
- **Output**: `[ { "id": "1", "name": "Marina Beach", "district": "Chennai" }, ... ]`

### Boat Management

#### `POST /boat/register` (Owner Only)
- **Input**: `{ "name": "Sea Hawk", "registration_number": "TN-01-1234", "device_id": "1234" }`
- **Output**: `{ "boat_id": "uuid...", "device_password": "secure_password" }`

#### `GET /boat/device-password` (Owner Only)
- **Input**: `?device_id=1234`
- **Output**: `{ "password": "secure_password" }`

#### `POST /boat/join` (Joiner/Land User)
- **Input**: `{ "qr_code": "encrypted_string..." }`
- **Output**: `{ "success": true, "boat": { ... } }`

### Device Integration

#### `POST /device/associate`
- **Input**: `{ "device_id": "1234", "boat_id": "uuid..." }`
- **Output**: `{ "success": true }`

## Mock Implementation Notes
- All calls will be simulated with `Future.delayed`.
- Data will be stored in-memory in `BackendService` or `SessionService` for the session duration.
