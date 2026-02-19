'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { createClient } from '@/utils/supabase/client';
import { ArrowLeft, Loader2, Pencil, Save, X, Navigation } from 'lucide-react';
import styles from './table-page-v2.module.css';

export default function TablePage() {
    const { tableName } = useParams();
    const router = useRouter();
    const supabase = createClient();
    const [data, setData] = useState<any[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    // Editing State
    const [editingRecord, setEditingRecord] = useState<any | null>(null);
    const [formData, setFormData] = useState<any>({});
    const [saving, setSaving] = useState(false);

    const table = Array.isArray(tableName) ? tableName[0] : tableName;

    const fetchData = async () => {
        setLoading(true);
        setError(null);

        if (!table) return;

        let query = supabase
            .from(table)
            .select(table === 'boats' ? '*, village:villages(name)' : '*')
            .order('created_at', { ascending: false });

        const { data: result, error: fetchError } = await query;

        if (fetchError) {
            console.error('Error fetching data:', fetchError);
            setError(fetchError.message);
        } else {
            setData(result || []);
        }
        setLoading(false);
    };

    useEffect(() => {
        fetchData();
    }, [table]);

    const handleEdit = (record: any) => {
        setEditingRecord(record);
        setFormData({ ...record });
    };

    // ... handleSave default ...

    const formatValue = (key: string, value: any, row?: any) => {
        if (value === null || value === undefined) return <span className="text-gray-600">-</span>;

        if (key === 'village' && typeof value === 'object') {
            return value?.name || '-';
        }

        if (typeof value === 'boolean') {
            return (
                <span className={`px-2 py-1 rounded-full text-xs ${value ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'}`}>
                    {String(value)}
                </span>
            );
        }

        if (key.includes('id') && typeof value === 'string') {
            return <span title={value} className={styles.idCell}>{value.substring(0, 8)}...</span>;
        }
        if (key === 'created_at' || key === 'updated_at' || key.includes('_at')) {
            return new Date(value).toLocaleDateString() + ' ' + new Date(value).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        }
        if (typeof value === 'object') {
            return <span className="text-xs text-gray-500 italic">{JSON.stringify(value).substring(0, 20)}...</span>;
        }
        return String(value);
    };

    // Column Definitions
    const getColumns = () => {
        if (table === 'boats') {
            return [
                { key: 'id', label: 'Boat ID' },
                { key: 'registration_number', label: 'Registration Number' },
                { key: 'name', label: 'Boat Name' },
                { key: 'village', label: 'Village' }
            ];
        }
        // Default: dynamic columns from data
        if (data.length > 0) {
            return Object.keys(data[0])
                .filter(k => k !== 'village') // exclude joined object if present by accident
                .map(key => ({ key, label: key.replace(/_/g, ' ') }));
        }
        return [];
    };

    const columns = getColumns();

    return (
        <div className={styles.container}>
            <div className={styles.header}>
                <div>
                    <h1 className={styles.title}>{table?.replace(/_/g, ' ')}</h1>
                    <p className={styles.subtitle}>Manage {table} records</p>
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
                                    {columns.map((col) => (
                                        <th key={col.key} className={styles.th}>
                                            {col.label}
                                        </th>
                                    ))}
                                    <th className={styles.th}>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                {data.map((row) => (
                                    <tr key={row.id} className={styles.tr}>
                                        {columns.map((col) => (
                                            <td key={col.key} className={styles.td}>
                                                {formatValue(col.key, row[col.key], row)}
                                            </td>
                                        ))}
                                        <td className={styles.td}>
                                            <div className="flex gap-2">
                                                <button
                                                    onClick={() => router.push(`/map?boatId=${row.id}`)}
                                                    className={styles.actionBtn}
                                                    title="View on Map"
                                                >
                                                    <Navigation size={16} />
                                                </button>
                                                <button
                                                    onClick={() => handleEdit(row)}
                                                    className={styles.actionBtn}
                                                    title="Edit Record"
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
                        <h2 className={styles.dialogTitle}>Edit Record</h2>
                        <div className="max-h-[60vh] overflow-y-auto pr-2">
                            {Object.entries(formData).map(([key, value]) => {
                                if (key === 'id' || key === 'created_at' || key === 'updated_at') return null;
                                return (
                                    <div key={key} className={styles.formGroup}>
                                        <label className={styles.label}>{key.replace(/_/g, ' ')}</label>
                                        <input
                                            type={typeof value === 'number' ? 'number' : 'text'}
                                            className={styles.input}
                                            value={value as string || ''}
                                            onChange={(e) => setFormData({ ...formData, [key]: e.target.value })}
                                            disabled={key.includes('_id')} // Disable editing foreign keys for safety for now
                                        />
                                    </div>
                                );
                            })}
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
