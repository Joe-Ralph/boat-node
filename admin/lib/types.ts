export type Profile = {
    id: string;
    email: string | null;
    display_name: string | null;
    role: 'owner' | 'crew' | 'land_user' | 'land_admin' | 'super_admin' | null;
    village_id: string | null;
    boat_id: string | null;
    created_at: string;
    updated_at: string;
};

export type Village = {
    id: string;
    name: string;
    district: string;
    created_at: string;
};

export type Boat = {
    id: string;
    name: string;
    registration_number: string | null;
    owner_id: string | null;
    village_id: string | null;
    device_id: string | null;
    created_at: string;
};

export type BoatLog = {
    id: number;
    boat_id: string | null;
    lat: number;
    lon: number;
    battery_level: number | null;
    speed: number | null;
    heading: number | null;
    recorded_at: string;
};
