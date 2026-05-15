/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/
import React, { useEffect, useState } from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import Docs from './components/Docs';
import SiteNav from './components/SiteNav';

const Root: React.FC = () => {
    const [hash, setHash] = useState<string>(window.location.hash);

    useEffect(() => {
        const onHash = () => {
            setHash(window.location.hash);
            window.scrollTo(0, 0);
        };
        window.addEventListener('hashchange', onHash);
        return () => window.removeEventListener('hashchange', onHash);
    }, []);

    const isDocs = hash.startsWith('#/docs');

    return (
        <>
            <SiteNav />
            {isDocs ? <Docs /> : <App />}
        </>
    );
};

const rootElement = document.getElementById('root');
if (!rootElement) {
    throw new Error("Could not find root element to mount to");
}

const root = ReactDOM.createRoot(rootElement);
root.render(
    <React.StrictMode>
        <Root />
    </React.StrictMode>
);
