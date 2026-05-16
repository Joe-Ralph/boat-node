export interface LoaderProgress {
    loaded: number;
    total: number;
    name?: string;
}

export type LoaderTask = () => Promise<void>;

export class Loader {
    private tasks: { name: string; run: LoaderTask }[] = [];

    add(name: string, run: LoaderTask) {
        this.tasks.push({ name, run });
    }

    async run(onProgress?: (p: LoaderProgress) => void): Promise<void> {
        const total = this.tasks.length;
        for (let i = 0; i < total; i++) {
            const t = this.tasks[i];
            try {
                await t.run();
            } catch (err) {
                console.warn('[Loader] task failed:', t.name, err);
            }
            onProgress?.({ loaded: i + 1, total, name: t.name });
        }
    }
}
