// Import the functions you need from the SDKs you need
import { initializeApp } from "firebase/app";
import { getAnalytics } from "firebase/analytics";
// TODO: Add SDKs for Firebase products that you want to use
// https://firebase.google.com/docs/web/setup#available-libraries

// Your web app's Firebase configuration
// For Firebase JS SDK v7.20.0 and later, measurementId is optional
const firebaseConfig = {
    apiKey: "AIzaSyBrJuee3o8seoIK1yrZJPQ57kPYIQbPQhQ",
    authDomain: "nedu-ec16b.firebaseapp.com",
    projectId: "nedu-ec16b",
    storageBucket: "nedu-ec16b.firebasestorage.app",
    messagingSenderId: "46773573328",
    appId: "1:46773573328:web:ea35816fa0affb67ab70d5",
    measurementId: "G-NKX9KWDH0Q"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);
const analytics = getAnalytics(app);

export { app, analytics };
