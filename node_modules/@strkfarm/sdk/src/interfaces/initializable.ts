export abstract class Initializable {
    protected initialized: boolean;

    constructor() {
        this.initialized = false;
    }
    
    abstract init(): Promise<void>;

    async waitForInitilisation() {
        return new Promise<void>((resolve, reject) => {
            const interval = setInterval(() => {
                if (this.initialized) {
                    console.log('Initialised');
                    clearInterval(interval);
                    resolve();
                }
            }, 1000);
        });
    }
}