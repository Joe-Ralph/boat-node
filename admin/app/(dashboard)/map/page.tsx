import BoatMap from '@/components/map/MapWrapper';
import styles from './map-page.module.css';

export default function MapPage() {
    return (
        <div className={styles.container}>
            <div className={styles.header}>
                <div>
                    <h1 className={styles.title}>Live Operations</h1>
                    <p className={styles.subtitle}>Real-time monitoring of all active fleet units</p>
                </div>
                <div className={styles.statusBadge}>
                    All Systems Normal
                </div>
            </div>

            <div className={styles.mapWrapper}>
                <BoatMap />
            </div>
        </div>
    );
}
