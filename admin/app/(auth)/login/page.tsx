'use client';

import { useState } from 'react';
import { createClient } from '@/utils/supabase/client';
import { useRouter } from 'next/navigation';
import { Mail, Loader2, KeyRound } from 'lucide-react';
import styles from './login.module.css';

export default function LoginPage() {
    const [email, setEmail] = useState('');
    const [otp, setOtp] = useState('');
    const [step, setStep] = useState<'email' | 'otp'>('email');
    const [loading, setLoading] = useState(false);
    const [message, setMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);
    const router = useRouter();
    const supabase = createClient();

    const handleSendOtp = async (e: React.FormEvent) => {
        e.preventDefault();

        // DEV BYPASS
        if (email === 'admin@example.com') {
            document.cookie = "dev_bypass=true; path=/";
            window.location.href = '/map';
            return;
        }

        setLoading(true);
        setMessage(null);

        try {
            const { error } = await supabase.auth.signInWithOtp({
                email,
                options: {
                    shouldCreateUser: false, // Only allow existing users (admins)
                },
            });

            if (error) throw error;

            setStep('otp');
            setMessage({ type: 'success', text: 'OTP sent! Check your email.' });
        } catch (error: any) {
            setMessage({ type: 'error', text: error.message || 'An error occurred' });
        } finally {
            setLoading(false);
        }
    };

    const handleVerifyOtp = async (e: React.FormEvent) => {
        e.preventDefault();
        setLoading(true);
        setMessage(null);

        try {
            const { error } = await supabase.auth.verifyOtp({
                email,
                token: otp,
                type: 'email',
            });

            if (error) throw error;

            router.push('/map');
            router.refresh();
        } catch (error: any) {
            setMessage({ type: 'error', text: error.message || 'Invalid OTP' });
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className={styles.container}>
            <div className={styles.overlay}></div>

            <div className={styles.card}>
                <div className={styles.header}>
                    <div className={styles.iconWrapper}>
                        {step === 'email' ? <Mail size={24} /> : <KeyRound size={24} />}
                    </div>
                    <h1 className={styles.title}>{step === 'email' ? 'Welcome Back' : 'Enter OTP'}</h1>
                    <p className={styles.subtitle}>
                        {step === 'email'
                            ? 'Sign in to access the Boat Node Admin Panel'
                            : `Code sent to ${email}`}
                    </p>
                </div>

                {step === 'email' ? (
                    <form onSubmit={handleSendOtp} className={styles.form}>
                        <div className={styles.inputGroup}>
                            <label className={styles.label}>Email Address</label>
                            <input
                                type="email"
                                value={email}
                                onChange={(e) => setEmail(e.target.value)}
                                placeholder="admin@example.com"
                                required
                                className={styles.input}
                            />
                        </div>

                        {message && (
                            <div className={`${styles.message} ${message.type === 'success' ? styles.success : styles.error}`}>
                                {message.text}
                            </div>
                        )}

                        <button
                            type="submit"
                            disabled={loading}
                            className={styles.button}
                        >
                            {loading ? <Loader2 className={styles.spinner} size={18} /> : 'Send OTP'}
                        </button>
                    </form>
                ) : (
                    <form onSubmit={handleVerifyOtp} className={styles.form}>
                        <div className={styles.inputGroup}>
                            <label className={styles.label}>6-Digit Code</label>
                            <input
                                type="text"
                                value={otp}
                                onChange={(e) => setOtp(e.target.value)}
                                placeholder="123456"
                                required
                                maxLength={6}
                                className={`${styles.input} text-center text-2xl tracking-widest`}
                            />
                        </div>

                        {message && (
                            <div className={`${styles.message} ${message.type === 'success' ? styles.success : styles.error}`}>
                                {message.text}
                            </div>
                        )}

                        <button
                            type="submit"
                            disabled={loading}
                            className={styles.button}
                        >
                            {loading ? <Loader2 className={styles.spinner} size={18} /> : 'Verify & Login'}
                        </button>

                        <button
                            type="button"
                            onClick={() => setStep('email')}
                            className="text-sm text-gray-400 hover:text-white transition-colors"
                        >
                            Back to Email
                        </button>
                    </form>
                )}
            </div>
        </div>
    );
}
