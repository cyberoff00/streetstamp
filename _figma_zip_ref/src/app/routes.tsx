import { createBrowserRouter } from "react-router";
import { Home } from "./pages/Home";
import { Tracking } from "./pages/Tracking";
import { Memories } from "./pages/Memories";
import { Cities } from "./pages/Cities";
import { Profile } from "./pages/Profile";
import { Equipment } from "./pages/Equipment";
import { About } from "./pages/About";
import { Privacy } from "./pages/Privacy";
import { Settings } from "./pages/Settings";

export const router = createBrowserRouter([
  {
    path: "/",
    Component: Home,
  },
  {
    path: "/tracking",
    Component: Tracking,
  },
  {
    path: "/memories",
    Component: Memories,
  },
  {
    path: "/cities",
    Component: Cities,
  },
  {
    path: "/profile",
    Component: Profile,
  },
  {
    path: "/equipment",
    Component: Equipment,
  },
  {
    path: "/settings",
    Component: Settings,
  },
  {
    path: "/about",
    Component: About,
  },
  {
    path: "/privacy",
    Component: Privacy,
  },
]);