import { motion } from "motion/react";
import { Calendar, Footprints, Route } from "lucide-react";
import { MainTabLayout } from "../components/MainTabLayout";

interface LifelogDay {
  id: string;
  date: string;
  city: string;
  distance: string;
  note: string;
}

const lifelogDays: LifelogDay[] = [
  {
    id: "l-1",
    date: "Feb 21, 2026",
    city: "London",
    distance: "8.4 km",
    note: "Walked along the Thames and recorded 3 memories.",
  },
  {
    id: "l-2",
    date: "Feb 20, 2026",
    city: "Oxford",
    distance: "5.1 km",
    note: "Short route around city center and train station.",
  },
  {
    id: "l-3",
    date: "Feb 19, 2026",
    city: "Shanghai",
    distance: "12.2 km",
    note: "Airport transfer day with long terminal walking.",
  },
];

export function Lifelog() {
  return (
    <MainTabLayout title="Lifelog">
      <section className="mx-auto w-full max-w-xl space-y-4">
        {lifelogDays.map((day, index) => (
          <motion.article
            key={day.id}
            initial={{ y: 20, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            transition={{ delay: index * 0.08 }}
            className="rounded-[32px] bg-white p-5 shadow-[0_6px_32px_rgba(0,0,0,0.05)]"
          >
            <div className="flex items-start justify-between gap-3">
              <div>
                <h3 className="text-lg font-black tracking-tight">{day.city}</h3>
                <div className="mt-1 inline-flex items-center gap-1 text-xs font-semibold uppercase tracking-wide text-[#6B6B6B]">
                  <Calendar className="h-3.5 w-3.5 stroke-[1.8]" />
                  <span>{day.date}</span>
                </div>
              </div>
              <div className="rounded-full bg-[#F5F5F3] px-3 py-1 text-[10px] font-black uppercase tracking-wider text-[#4A4A4A]">
                {day.distance}
              </div>
            </div>

            <p className="mt-3 text-sm leading-relaxed text-[#555]">{day.note}</p>

            <div className="mt-4 flex items-center gap-3 rounded-[20px] bg-[#FBFBF9] px-4 py-3">
              <Footprints className="h-4 w-4 stroke-[1.8] text-[#B8947D]" />
              <span className="text-xs font-semibold uppercase tracking-wide text-[#6B6B6B]">Passive tracking enabled</span>
              <Route className="ml-auto h-4 w-4 stroke-[1.8] text-[#52B788]" />
            </div>
          </motion.article>
        ))}
      </section>
    </MainTabLayout>
  );
}
