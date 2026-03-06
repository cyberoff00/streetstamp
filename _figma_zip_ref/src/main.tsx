import { createRoot } from "react-dom/client";
import App from "./app/App.tsx";
import { reportWebVitals } from "./reportWebVitals";
import "./styles/index.css";

createRoot(document.getElementById("root")!).render(<App />);
reportWebVitals();
