# Supabase Schema & Roles

## Database Schema

### Tables

#### `users`
| Column | Type | Description |
|---|---|---|
| `id` | UUID | Primary Key |
| `phone_number` | Text | Unique phone number |
| `display_name` | Text | User's full name |
| `role` | Text | Enum: 'owner', 'joiner', 'land_user', 'land_admin', 'super_user' |
| `village_id` | UUID | Foreign Key to `villages` |
| `boat_id` | UUID | Foreign Key to `boats` (if joined/owned) |
| `created_at` | Timestamp | Creation time |

#### `boats`
| Column | Type | Description |
|---|---|---|
| `id` | UUID | Primary Key |
| `name` | Text | Boat Name |
| `registration_number` | Text | Official Registration Number |
| `device_id` | Text | Unique Device ID (e.g., MAC address or Serial) |
| `device_password` | Text | Wi-Fi Password for the device |
| `owner_id` | UUID | Foreign Key to `users` (Owner) |
| `village_id` | UUID | Foreign Key to `villages` |
| `created_at` | Timestamp | Creation time |

#### `villages`
| Column | Type | Description |
|---|---|---|
| `id` | UUID | Primary Key |
| `name` | Text | Village Name |
| `district` | Text | District Name |

### Roles & Responsibilities

1.  **Boat Owner**
    *   **Objective**: Manage and operate the boat.
    *   **Permissions**: Pair device, register boat, generate QR, full app access.
    *   **Data Access**: Read/Write own boat data.

2.  **Boat Joiner**
    *   **Objective**: Crew member joining for fishing.
    *   **Permissions**: Connect via QR, SOS, View Nearby. No device reset.
    *   **Data Access**: Read joined boat data.

3.  **Land User**
    *   **Objective**: Track specific boat from land.
    *   **Permissions**: View Dashboard/Map (Internet only). No module comms.
    *   **Data Access**: Read joined boat location/status.

4.  **Land Admin**
    *   **Objective**: Monitor all boats in a village.
    *   **Permissions**: View Map with all village boats. Requires approval.
    *   **Data Access**: Read all boats in assigned village.

5.  **Super User**
    *   **Objective**: System administration.
    *   **Permissions**: Full access via Web Admin Panel.
    *   **Data Access**: Global read/write.

## RLS Policies (Mock)

- **Users**: Can read own profile. Can update own profile.
- **Boats**:
    - Owner can read/update own boat.
    - Joiner/Land User can read joined boat.
    - Land Admin can read all boats in village.
- **Villages**: Public read access.
