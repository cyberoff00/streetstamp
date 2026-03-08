import { motion } from "motion/react";
import { Heart, MapPin, MessageCircle, Zap } from "lucide-react";
import { MainTabLayout } from "../components/MainTabLayout";

interface FriendActivity {
  id: string;
  name: string;
  city: string;
  status: string;
  level: string;
  accent: string;
}

const friends: FriendActivity[] = [
  { id: "f-1", name: "KIKO", city: "London", status: "shared a route 12m ago", level: "LV 14", accent: "#52B788" },
  { id: "f-2", name: "MORI", city: "Tokyo", status: "captured a memory 1h ago", level: "LV 11", accent: "#74C69D" },
  { id: "f-3", name: "NOA", city: "Seoul", status: "started a journey 3h ago", level: "LV 9", accent: "#B8947D" },
  { id: "f-4", name: "YUNA", city: "Berlin", status: "unlocked a city today", level: "LV 17", accent: "#3C9A71" },
];

export function Friends() {
  return (
    <MainTabLayout title="Friends">
      <section className="mx-auto w-full max-w-xl space-y-4">
        {friends.map((friend, index) => (
          <motion.article
            key={friend.id}
            initial={{ y: 20, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            transition={{ delay: index * 0.08 }}
            className="rounded-[32px] bg-white p-5 shadow-[0_6px_32px_rgba(0,0,0,0.05)]"
          >
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div
                  className="flex h-12 w-12 items-center justify-center rounded-[16px] text-white shadow-sm"
                  style={{ backgroundColor: friend.accent }}
                >
                  <Heart className="h-5 w-5 stroke-[2]" />
                </div>
                <div>
                  <h3 className="text-lg font-black tracking-tight">{friend.name}</h3>
                  <p className="text-xs font-semibold uppercase tracking-wide text-[#6B6B6B]">{friend.level}</p>
                </div>
              </div>
              <div className="rounded-full bg-[#F5F5F3] px-3 py-1 text-[10px] font-black uppercase tracking-wider">
                Active
              </div>
            </div>

            <div className="mt-4 flex items-center gap-2 text-sm text-[#4F4F4F]">
              <MapPin className="h-4 w-4 stroke-[1.8]" />
              <span>{friend.city}</span>
            </div>

            <p className="mt-2 text-sm text-[#6B6B6B]">{friend.status}</p>

            <div className="mt-4 flex gap-2">
              <button className="flex-1 rounded-full bg-[#52B788] px-4 py-2 text-xs font-black uppercase tracking-wide text-white shadow-[0_4px_16px_rgba(82,183,136,0.24)]">
                <span className="inline-flex items-center gap-1">
                  <Zap className="h-3.5 w-3.5 stroke-[2]" />
                  Stomp
                </span>
              </button>
              <button className="flex-1 rounded-full bg-[#F5F5F3] px-4 py-2 text-xs font-black uppercase tracking-wide text-[#3F3F3F]">
                <span className="inline-flex items-center gap-1">
                  <MessageCircle className="h-3.5 w-3.5 stroke-[2]" />
                  Message
                </span>
              </button>
            </div>
          </motion.article>
        ))}
      </section>
    </MainTabLayout>
  );
}
