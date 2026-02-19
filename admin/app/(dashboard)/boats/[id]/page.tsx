'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { createClient } from '@/utils/supabase/client';
import { ArrowLeft, User, Battery, Navigation, Anchor } from 'lucide-react';
import { Boat, Profile } from '@/lib/types';

type BoatDetails = Boat & {
    village?: { name: string };
    owner?: { display_name: string; email: string };
    members?: (Profile & { joined_at: string; role: string })[];
};

export default function BoatDetailsPage() {
    const { id } = useParams();
    const router = useRouter();
    const supabase = createClient();
    const [boat, setBoat] = useState<BoatDetails | null>(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        const fetchBoatDetails = async () => {
            if (!id) return;

            // 1. Fetch Boat with owner and village
            const { data, error } = await supabase
                .from('boats')
                .select(`
          *,
          village:villages(name),
          owner:profiles!owner_id(display_name, email)
        `)
                .eq('id', id)
                .single();

            if (error) {
                console.error('Error fetching boat:', error);
                setLoading(false);
                return;
            }

            // 2. Fetch Members
            const { data: membersData, error: membersError } = await supabase
                .from('boat_members')
                .select(`
          role,
          joined_at,
          profile:profiles!user_id(*)
        `)
                .eq('boat_id', id);

            const members = membersData?.map((m: any) => ({
                ...m.profile,
                role: m.role,
                joined_at: m.joined_at,
            })) || [];

            setBoat({ ...data, members });
            setLoading(false);
        };

        fetchBoatDetails();
    }, [id]);

    if (loading) {
        return (
            <div className="flex items-center justify-center h-full">
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
            </div>
        );
    }

    if (!boat) {
        return (
            <div className="p-8 text-center text-gray-400">
                Boat not found or access denied.
            </div>
        );
    }

    return (
        <div className="p-8 max-w-5xl mx-auto space-y-8">
            {/* Header */}
            <div className="flex items-center gap-4">
                <button
                    onClick={() => router.back()}
                    className="p-2 hover:bg-white/5 rounded-lg transition-colors border border-white/10"
                >
                    <ArrowLeft className="w-5 h-5 text-gray-400" />
                </button>
                <div>
                    <h1 className="text-3xl font-bold text-white flex items-center gap-3">
                        {boat.name}
                        <span className="text-sm font-normal bg-primary/10 text-primary px-3 py-1 rounded-full border border-primary/20">
                            {boat.registration_number}
                        </span>
                    </h1>
                    <p className="text-gray-400 mt-1">
                        Village: <span className="text-white">{boat.village?.name || 'Unknown'}</span> •
                        Owner: <span className="text-white">{boat.owner?.display_name || 'Unknown'}</span>
                    </p>
                </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                {/* Status Card */}
                <div className="card md:col-span-2 space-y-6">
                    <h2 className="text-xl font-semibold text-white border-b border-white/5 pb-4">Boat Overview</h2>

                    <div className="grid grid-cols-2 gap-4">
                        <div className="bg-white/5 p-4 rounded-xl border border-white/5">
                            <div className="flex items-center gap-2 text-gray-400 mb-2">
                                <Anchor className="w-4 h-4" />
                                <span>Device ID</span>
                            </div>
                            <p className="text-lg font-mono text-white">{boat.device_id || 'Not Linked'}</p>
                        </div>

                        <div className="bg-white/5 p-4 rounded-xl border border-white/5">
                            <div className="flex items-center gap-2 text-gray-400 mb-2">
                                <Battery className="w-4 h-4" />
                                <span>Status</span>
                            </div>
                            <div className="flex items-center gap-2">
                                <span className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></span>
                                <p className="text-lg text-white">Active</p>
                            </div>
                        </div>
                    </div>
                </div>

                {/* Crew List */}
                <div className="card space-y-4">
                    <div className="flex items-center justify-between border-b border-white/5 pb-4">
                        <h2 className="text-xl font-semibold text-white">Crew & Members</h2>
                        <span className="bg-white/10 text-xs px-2 py-1 rounded-md text-gray-300">
                            {boat.members?.length || 0} Joined
                        </span>
                    </div>

                    <div className="space-y-3">
                        {boat.members && boat.members.length > 0 ? (
                            boat.members.map((member) => (
                                <div key={member.id} className="flex items-center gap-3 p-3 bg-white/5 rounded-lg border border-white/5">
                                    <div className="w-10 h-10 rounded-full bg-primary/20 flex items-center justify-center text-primary">
                                        <User className="w-5 h-5" />
                                    </div>
                                    <div>
                                        <p className="text-sm font-medium text-white">{member.display_name || 'Anonymous'}</p>
                                        <p className="text-xs text-gray-400 capitalize">{member.role} • {new Date(member.joined_at!).toLocaleDateString()}</p>
                                    </div>
                                </div>
                            ))
                        ) : (
                            <p className="text-gray-500 text-center py-4">No members currently joined.</p>
                        )}
                    </div>
                </div>
            </div>
        </div>
    );
}
