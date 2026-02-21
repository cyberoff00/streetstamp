import { motion, AnimatePresence } from "motion/react";
import { useNavigate } from "react-router";
import { Menu, ChevronDown, Calendar } from "lucide-react";
import { useState } from "react";
import { HamburgerMenu } from "../components/HamburgerMenu";

interface Memory {
  id: string;
  date: string;
  text: string;
  location: string;
}

const mockMemories: Record<string, Memory[]> = {
  "上海市": [
    {
      id: "1",
      date: "Jan 29, 2026",
      text: "这是第一次从上海飞伦敦，即使只是中转站，这一切看着非常合理，比 22 年的深圳香港伦敦这样的路线在历史意义上来说更理所当然。...",
      location: "上海市",
    },
    {
      id: "2",
      date: "Jan 25, 2026",
      text: "待解决问题：\n2. 锁屏组件 UI\n3. 海拔前台显示...",
      location: "上海市",
    },
    {
      id: "3",
      date: "Jan 24, 2026",
      text: "明天就要去济州岛了，我希望带着轻盈的心出发，很多事情都在发生，但我的精神仅仅是吸纳在这个 app 里了，我感到疲惫，感到解离。",
      location: "上海市",
    },
  ],
  伦敦: [
    {
      id: "4",
      date: "Feb 1, 2026",
      text: "今天探索了泰晤士河畔，天气很好。",
      location: "伦敦",
    },
  ],
  杭州: [
    {
      id: "5",
      date: "Jan 20, 2026",
      text: "西湖边散步，心情很平静。",
      location: "杭州",
    },
  ],
};

export function Memories() {
  const navigate = useNavigate();
  const [expandedCities, setExpandedCities] = useState<string[]>(["上海市"]);
  const [menuOpen, setMenuOpen] = useState(false);

  const toggleCity = (city: string) => {
    setExpandedCities((prev) =>
      prev.includes(city) ? prev.filter((c) => c !== city) : [...prev, city]
    );
  };

  return (
    <div className="min-h-screen bg-[#FBFBF9]">
      {/* Header */}
      <motion.header
        initial={{ y: -50, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        transition={{ duration: 0.5 }}
        className="sticky top-0 z-10 bg-white/90 backdrop-blur-2xl border-b border-black/[0.06]"
      >
        <div className="px-6 py-6 flex items-center justify-between">
          <motion.button
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            onClick={() => setMenuOpen(true)}
            className="p-2 rounded-full hover:bg-black/5 transition-all"
          >
            <Menu className="w-6 h-6 stroke-[1.5]" />
          </motion.button>
          <h1 className="text-3xl font-black tracking-tight uppercase">Memories</h1>
          <div className="w-10" />
        </div>
      </motion.header>

      {/* Memories List */}
      <div className="px-6 py-8 space-y-4">
        {Object.entries(mockMemories).map(([city, memories], index) => (
          <CityMemoryGroup
            key={city}
            city={city}
            memories={memories}
            isExpanded={expandedCities.includes(city)}
            onToggle={() => toggleCity(city)}
            index={index}
          />
        ))}
      </div>

      {/* Hamburger Menu */}
      <HamburgerMenu isOpen={menuOpen} onClose={() => setMenuOpen(false)} />
    </div>
  );
}

function CityMemoryGroup({
  city,
  memories,
  isExpanded,
  onToggle,
  index,
}: {
  city: string;
  memories: Memory[];
  isExpanded: boolean;
  onToggle: () => void;
  index: number;
}) {
  return (
    <motion.div
      initial={{ y: 50, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ delay: index * 0.08 }}
    >
      {/* City Header */}
      <motion.button
        whileHover={{ scale: 1.01 }}
        whileTap={{ scale: 0.99, filter: "brightness(1.05)" }}
        onClick={onToggle}
        className="w-full bg-white rounded-[32px] shadow-[0_4px_32px_rgba(0,0,0,0.04)] p-6 flex items-center justify-between active:shadow-[inset_0_2px_12px_rgba(0,0,0,0.06)] transition-all"
      >
        <div className="text-left">
          <h3 className="text-xl font-black tracking-tight">{city}</h3>
          <p className="text-xs text-[#6B6B6B] mt-1 tracking-wide uppercase font-semibold">{memories.length} Records</p>
        </div>
        <motion.div
          animate={{ rotate: isExpanded ? 180 : 0 }}
          transition={{ duration: 0.3 }}
        >
          <ChevronDown className="w-6 h-6 stroke-[1.5] text-[#6B6B6B]" />
        </motion.div>
      </motion.button>

      {/* Memories */}
      <AnimatePresence>
        {isExpanded && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.3 }}
            className="overflow-hidden"
          >
            <div className="mt-4 space-y-3">
              {memories.map((memory, memIndex) => (
                <MemoryCard key={memory.id} memory={memory} index={memIndex} />
              ))}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}

function MemoryCard({ memory, index }: { memory: Memory; index: number }) {
  return (
    <motion.div
      initial={{ x: -50, opacity: 0 }}
      animate={{ x: 0, opacity: 1 }}
      transition={{ delay: index * 0.05 }}
      whileHover={{ scale: 1.01, x: 4 }}
      className="bg-white rounded-[28px] shadow-[0_4px_24px_rgba(0,0,0,0.04)] p-5 border-l-4 border-[#A8BDB5]"
    >
      <div className="flex items-center gap-2 mb-3">
        <div className="w-2 h-2 rounded-full bg-[#A8BDB5]" />
        <Calendar className="w-4 h-4 stroke-[1.5] text-[#6B6B6B]" />
        <span className="text-xs font-black text-[#6B6B6B] tracking-wide uppercase">{memory.date}</span>
      </div>
      <p className="text-black leading-relaxed tracking-normal">{memory.text}</p>
    </motion.div>
  );
}