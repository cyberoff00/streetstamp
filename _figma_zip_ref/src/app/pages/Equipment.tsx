import { motion } from "motion/react";
import { useNavigate } from "react-router";
import { ArrowLeft, Backpack, Camera, Compass, Book, Map, Clock, Telescope, Tent, Check, ShoppingCart, Coins } from "lucide-react";
import { useState } from "react";

interface EquipmentItem {
  id: string;
  name: string;
  description: string;
  IconComponent: React.ComponentType<{ className?: string }>;
  owned: boolean;
  equipped: boolean;
  price?: number;
  rarity: "common" | "rare" | "epic" | "legendary";
}

const equipment: EquipmentItem[] = [
  {
    id: "1",
    name: "探险者背包",
    description: "基础款背包，可以携带更多物品",
    IconComponent: Backpack,
    owned: true,
    equipped: true,
    rarity: "common",
  },
  {
    id: "2",
    name: "专业相机",
    description: "记录更清晰的回忆",
    IconComponent: Camera,
    owned: true,
    equipped: false,
    rarity: "rare",
  },
  {
    id: "3",
    name: "指南针",
    description: "永远不会迷失方向",
    IconComponent: Compass,
    owned: false,
    equipped: false,
    price: 50,
    rarity: "common",
  },
  {
    id: "4",
    name: "旅行日记",
    description: "记录每一次探险的故事",
    IconComponent: Book,
    owned: true,
    equipped: true,
    rarity: "rare",
  },
  {
    id: "5",
    name: "魔法地图",
    description: "显示隐藏的秘密地点",
    IconComponent: Map,
    owned: false,
    equipped: false,
    price: 200,
    rarity: "epic",
  },
  {
    id: "6",
    name: "时光沙漏",
    description: "让时间变慢，享受每一刻",
    IconComponent: Clock,
    owned: false,
    equipped: false,
    price: 500,
    rarity: "legendary",
  },
  {
    id: "7",
    name: "望远镜",
    description: "看见更远的风景",
    IconComponent: Telescope,
    owned: false,
    equipped: false,
    price: 80,
    rarity: "rare",
  },
  {
    id: "8",
    name: "露营帐篷",
    description: "随时随地安营扎寨",
    IconComponent: Tent,
    owned: true,
    equipped: false,
    rarity: "common",
  },
];

const rarityColors = {
  common: "bg-[#F5F5F3]",
  rare: "bg-[#52B788]/10",
  epic: "bg-[#74C69D]/15",
  legendary: "bg-[#B8947D]/20",
};

const rarityLabels = {
  common: "COMMON",
  rare: "RARE",
  epic: "EPIC",
  legendary: "LEGEND",
};

export function Equipment() {
  const navigate = useNavigate();
  const [selectedTab, setSelectedTab] = useState<"owned" | "shop">("owned");

  const ownedItems = equipment.filter((item) => item.owned);
  const shopItems = equipment.filter((item) => !item.owned);

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
            onClick={() => navigate("/profile")}
            className="flex items-center gap-2 p-2 rounded-full hover:bg-black/5 transition-all"
          >
            <ArrowLeft className="w-5 h-5 stroke-[1.5]" />
            <span className="font-black text-sm tracking-tight uppercase">Back</span>
          </motion.button>
          <h1 className="text-3xl font-black tracking-tight uppercase">Equipment</h1>
          <div className="flex items-center gap-2 px-4 py-2 bg-[#52B788]/10 rounded-full">
            <Coins className="w-5 h-5 stroke-[1.5] text-[#52B788]" />
            <span className="font-black text-sm">100</span>
          </div>
        </div>
      </motion.header>

      {/* Tabs */}
      <div className="px-6 py-6">
        <div className="bg-white rounded-[28px] p-2 flex gap-2 shadow-[0_4px_24px_rgba(0,0,0,0.04)]">
          <TabButton
            active={selectedTab === "owned"}
            onClick={() => setSelectedTab("owned")}
            label="MY GEAR"
          />
          <TabButton
            active={selectedTab === "shop"}
            onClick={() => setSelectedTab("shop")}
            label="SHOP"
          />
        </div>
      </div>

      {/* Equipment Grid */}
      <div className="px-6 pb-8">
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
          {(selectedTab === "owned" ? ownedItems : shopItems).map((item, index) => (
            <EquipmentCard key={item.id} item={item} index={index} tab={selectedTab} />
          ))}
        </div>
      </div>
    </div>
  );
}

function TabButton({
  active,
  onClick,
  label,
}: {
  active: boolean;
  onClick: () => void;
  label: string;
}) {
  return (
    <motion.button
      whileTap={{ scale: 0.98, filter: "brightness(1.1)" }}
      onClick={onClick}
      className={`flex-1 px-6 py-3 rounded-[20px] font-black text-sm tracking-tight uppercase transition-all ${
        active
          ? "bg-black text-white shadow-[0_4px_16px_rgba(0,0,0,0.15)]"
          : "bg-transparent text-[#6B6B6B] hover:bg-[#F5F5F3]"
      }`}
    >
      {label}
    </motion.button>
  );
}

function EquipmentCard({
  item,
  index,
  tab,
}: {
  item: EquipmentItem;
  index: number;
  tab: "owned" | "shop";
}) {
  const IconComp = item.IconComponent;
  
  return (
    <motion.div
      initial={{ scale: 0.9, opacity: 0, y: 30 }}
      animate={{ scale: 1, opacity: 1, y: 0 }}
      transition={{
        delay: index * 0.05,
        type: "spring",
        stiffness: 200,
        damping: 20,
      }}
      whileHover={{ scale: 1.03, y: -4 }}
      whileTap={{ scale: 0.98 }}
      className="group cursor-pointer"
    >
      <div
        className={`${
          rarityColors[item.rarity]
        } rounded-[28px] shadow-[0_4px_24px_rgba(0,0,0,0.04)] overflow-hidden relative`}
      >
        {/* Equipped Badge */}
        {item.equipped && (
          <div className="absolute top-3 right-3 bg-[#B8947D] text-white text-[10px] px-3 py-1 rounded-full font-black tracking-wider uppercase z-10 flex items-center gap-1">
            <Check className="w-3 h-3 stroke-[2]" />
            <span>EQUIPPED</span>
          </div>
        )}

        {/* Icon */}
        <div className="p-8 flex items-center justify-center">
          <motion.div
            whileHover={{ rotate: [0, -8, 8, -8, 0] }}
            transition={{ duration: 0.5 }}
          >
            <IconComp className="w-16 h-16 stroke-[1.5] text-black" />
          </motion.div>
        </div>

        {/* Info */}
        <div className="p-4 bg-white/90 backdrop-blur-sm">
          <div className="flex items-center justify-between mb-2">
            <h3 className="font-black text-sm tracking-tight">{item.name}</h3>
            <span className="text-[9px] px-2 py-1 bg-[#F5F5F3] rounded-full font-black tracking-wider uppercase">
              {rarityLabels[item.rarity]}
            </span>
          </div>
          <p className="text-xs text-[#6B6B6B] mb-3 leading-relaxed">{item.description}</p>

          {/* Action Button */}
          {tab === "shop" ? (
            <motion.button
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98, filter: "brightness(1.2)" }}
              className="w-full bg-black text-white py-2.5 rounded-full font-black text-xs tracking-tight uppercase flex items-center justify-center gap-2 shadow-[0_4px_16px_rgba(0,0,0,0.15)] active:shadow-[inset_0_2px_12px_rgba(255,255,255,0.2)]"
            >
              <Coins className="w-4 h-4 stroke-[1.5]" />
              <span>{item.price}</span>
              <ShoppingCart className="w-4 h-4 stroke-[1.5]" />
            </motion.button>
          ) : (
            <motion.button
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98, filter: "brightness(1.1)" }}
              className={`w-full py-2.5 rounded-full font-black text-xs tracking-tight uppercase transition-all ${
                item.equipped
                  ? "bg-[#F5F5F3] text-[#6B6B6B]"
                  : "bg-[#52B788] text-white shadow-[0_4px_16px_rgba(82,183,136,0.25)] active:shadow-[inset_0_2px_12px_rgba(255,255,255,0.15)]"
              }`}
            >
              {item.equipped ? "EQUIPPED" : "EQUIP"}
            </motion.button>
          )}
        </div>

        {/* Hover Glow Effect */}
        <motion.div
          className="absolute inset-0 rounded-[28px] opacity-0 group-hover:opacity-100 pointer-events-none transition-opacity"
          style={{
            boxShadow: "inset 0 0 0 2px #52B788, 0 0 20px rgba(82, 183, 136, 0.25)",
          }}
        />
      </div>
    </motion.div>
  );
}