import { createBrowserRouter } from "react-router";

export const router = createBrowserRouter([
  {
    path: "/",
    lazy: async () => ({ Component: (await import("./pages/Home")).Home }),
  },
  {
    path: "/tracking",
    lazy: async () => ({ Component: (await import("./pages/Tracking")).Tracking }),
  },
  {
    path: "/friends",
    lazy: async () => ({ Component: (await import("./pages/Friends")).Friends }),
  },
  {
    path: "/lifelog",
    lazy: async () => ({ Component: (await import("./pages/Lifelog")).Lifelog }),
  },
  {
    path: "/memories",
    lazy: async () => ({ Component: (await import("./pages/Memories")).Memories }),
  },
  {
    path: "/cities",
    lazy: async () => ({ Component: (await import("./pages/Cities")).Cities }),
  },
  {
    path: "/profile",
    lazy: async () => ({ Component: (await import("./pages/Profile")).Profile }),
  },
  {
    path: "/equipment",
    lazy: async () => ({ Component: (await import("./pages/Equipment")).Equipment }),
  },
  {
    path: "/settings",
    lazy: async () => ({ Component: (await import("./pages/Settings")).Settings }),
  },
  {
    path: "/about",
    lazy: async () => ({ Component: (await import("./pages/About")).About }),
  },
  {
    path: "/privacy",
    lazy: async () => ({ Component: (await import("./pages/Privacy")).Privacy }),
  },
]);
