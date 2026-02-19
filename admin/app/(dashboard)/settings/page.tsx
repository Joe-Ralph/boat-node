'use client';

import { useEffect, useState } from 'react';
import { createClient } from '@/utils/supabase/client';
import { Loader2, Pencil, Save, X } from 'lucide-react';
import styles from './settings.module.css';

type AppSetting = {
    key: string;
    value: string;
    description: string | null;
};

export default function SettingsPage() {
    const supabase = createClient();
    const [settings, setSettings] = useState<AppSetting[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    // Editing State
    const [editingRecord, setEditingRecord] = useState<AppSetting | null>(null);
    const [editValue, setEditValue] = useState('');
    const [saving, setSaving] = useState(false);

    const fetchSettings = async () => {
        setLoading(true);
        const { data, error } = await supabase
            .from('app_settings')
            .select('*')
            .order('key');

        if (error) {
            console.error('Error fetching settings:', error);
            setError(error.message);
        } else {
            setSettings(data || []);
        }
        setLoading(false);
    };

    useEffect(() => {
        fetchSettings();
    }, []);

    const handleEdit = (record: AppSetting) => {
        setEditingRecord(record);
        setEditValue(record.value);
    };

    const handleSave = async () => {
        if (!editingRecord) return;
        setSaving(true);
        const { error } = await supabase
            .from('app_settings')
            .update({ value: editValue })
            .eq('key', editingRecord.key);

        if (error) {
            alert('Error saving setting: ' + error.message);
        } else {
            setEditingRecord(null);
            fetchSettings();
        }
        setSaving(false);
    };

    return (
        <div className={styles.container}>
            <div className={styles.header}>
                <div>
                    <h1 className={styles.title}>App Configuration</h1>
                    <p className={styles.subtitle}>Manage global application settings</p>
                </div>
            </div>

            {loading ? (
                <div className="flex justify-center p-12">
                    <Loader2 className="w-8 h-8 animate-spin text-sky-500" />
                </div>
            ) : error ? (
                <div className="p-4 bg-red-500/10 border border-red-500/20 rounded-xl text-red-400">
                    Error: {error}
                </div>
            ) : (
                <div className={styles.card}>
                    <div className={styles.tableContainer}>
                        <table className={styles.table}>
                            <thead>
                                <tr>
                                    <th className={styles.th}>Key</th>
                                    <th className={styles.th}>Value</th>
                                    <th className={styles.th}>Description</th>
                                    <th className={styles.th}>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                {settings.map((setting) => (
                                    <tr key={setting.key} className={styles.tr}>
                                        <td className={styles.td}>
                                            <span className={styles.keyCell}>{setting.key}</span>
                                        </td>
                                        <td className={styles.td}>
                                            <span className="text-white font-mono">{setting.value}</span>
                                        </td>
                                        <td className={styles.td}>
                                            {setting.description || '-'}
                                        </td>
                                        <td className={styles.td}>
                                            <div className="flex gap-2">
                                                <button
                                                    onClick={() => handleEdit(setting)}
                                                    className={styles.actionBtn}
                                                    title="Edit Setting"
                                                >
                                                    <Pencil size={16} />
                                                </button>
                                            </div>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </div>
            )}

            {/* Edit Dialog */}
            {editingRecord && (
                <div className={styles.dialogOverlay}>
                    <div className={styles.dialog}>
                        <div className="flex justify-between items-start mb-6">
                            <h2 className={styles.dialogTitle}>Edit Setting</h2>
                            <button onClick={() => setEditingRecord(null)} className="text-gray-400 hover:text-white">
                                <X size={20} />
                            </button>
                        </div>

                        <div className={styles.formGroup}>
                            <label className={styles.label}>Key</label>
                            <input
                                type="text"
                                className={styles.input}
                                value={editingRecord.key}
                                disabled
                                style={{ opacity: 0.5, cursor: 'not-allowed' }}
                            />
                        </div>

                        <div className={styles.formGroup}>
                            <label className={styles.label}>Description</label>
                            <p className="text-sm text-gray-400 mb-2">{editingRecord.description}</p>
                        </div>

                        <div className={styles.formGroup}>
                            <label className={styles.label}>Value</label>
                            <input
                                type="text"
                                className={styles.input}
                                value={editValue}
                                onChange={(e) => setEditValue(e.target.value)}
                                autoFocus
                            />
                        </div>

                        <div className={styles.dialogActions}>
                            <button
                                onClick={() => setEditingRecord(null)}
                                className={styles.cancelBtn}
                                disabled={saving}
                            >
                                Cancel
                            </button>
                            <button
                                onClick={handleSave}
                                className={styles.saveBtn}
                                disabled={saving}
                            >
                                {saving ? <Loader2 className="animate-spin" size={18} /> : 'Save Changes'}
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}
