import { RouterProvider } from 'react-router';
import { router } from './routes';

export default function App() {
  return (
    <RouterProvider
      router={router}
      fallbackElement={
        <div style={{ minHeight: "100vh", display: "grid", placeItems: "center", fontWeight: 600 }}>
          Loading...
        </div>
      }
    />
  );
}
