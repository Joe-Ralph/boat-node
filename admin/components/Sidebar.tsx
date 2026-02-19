'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Map, Table, Settings, LogOut, Ship } from 'lucide-react';
import { createClient } from '@/utils/supabase/client';
import { useRouter } from 'next/navigation';
import styles from './sidebar.module.css';

export default function Sidebar() {
    const pathname = usePathname();
    const router = useRouter();
    const supabase = createClient();

    const handleLogout = async () => {
        await supabase.auth.signOut();
        router.push('/login');
    };

    const navItems = [
        { name: 'Live Map', href: '/map', icon: Map },
        { name: 'Boats', href: '/tables/boats', icon: Ship },
        { name: 'Villages', href: '/tables/villages', icon: Table },
        { name: 'Settings', href: '/settings', icon: Settings },
    ];

    return (
        <aside className={styles.sidebar}>
            <div className={styles.header}>
                <h1 className={styles.title}>
                    <Ship size={24} color="#0ea5e9" suppressHydrationWarning />
                    Neduvaai
                </h1>
                <p className={styles.subtitle}>Admin Panel</p>
            </div>

            <nav className={styles.nav}>
                {navItems.map((item) => {
                    const isActive = pathname.startsWith(item.href);
                    return (
                        <Link
                            key={item.href}
                            href={item.href}
                            className={`${styles.navItem} ${isActive ? styles.active : ''}`}
                        >
                            <item.icon size={20} suppressHydrationWarning />
                            <span>{item.name}</span>
                        </Link>
                    );
                })}
            </nav>

            <div className={styles.footer}>
                <button
                    onClick={handleLogout}
                    className={styles.logoutBtn}
                >
                    <LogOut size={20} suppressHydrationWarning />
                    <span>Sign Out</span>
                </button>
            </div>
        </aside>
    );
}
