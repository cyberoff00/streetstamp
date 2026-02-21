import { motion, AnimatePresence } from "motion/react";
import { X, Eye } from "lucide-react";

export function ShareRouteModal({
  isOpen,
  onClose,
}: {
  isOpen: boolean;
  onClose: () => void;
}) {
  return (
    <AnimatePresence>
      {isOpen && (
        <>
          {/* Backdrop */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="fixed inset-0 bg-black/40 backdrop-blur-sm z-40"
          />

          {/* Modal */}
          <motion.div
            initial={{ opacity: 0, scale: 0.9, y: 50 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.9, y: 50 }}
            transition={{ type: "spring", damping: 25, stiffness: 300 }}
            className="fixed inset-8 md:inset-auto md:top-1/2 md:left-1/2 md:-translate-x-1/2 md:-translate-y-1/2 md:w-full md:max-w-2xl z-50"
          >
            <div className="bg-gradient-to-br from-white to-gray-50 rounded-3xl shadow-2xl overflow-hidden">
              {/* Header */}
              <div className="px-6 py-5 flex items-center justify-between border-b border-gray-200">
                <h3 className="text-2xl font-semibold">分享卡片</h3>
                <motion.button
                  whileHover={{ scale: 1.1, rotate: 90 }}
                  whileTap={{ scale: 0.9 }}
                  onClick={onClose}
                  className="p-2 hover:bg-gray-100 rounded-full transition-colors"
                >
                  <X className="w-5 h-5" />
                </motion.button>
              </div>

              {/* Content */}
              <div className="p-6">
                {/* Route Preview Card */}
                <motion.div
                  initial={{ scale: 0.95, opacity: 0 }}
                  animate={{ scale: 1, opacity: 1 }}
                  transition={{ delay: 0.1 }}
                  className="relative bg-white rounded-2xl shadow-lg overflow-hidden border-2 border-gray-100"
                >
                  {/* Map Preview */}
                  <div className="relative h-64 bg-gradient-to-br from-green-100 to-emerald-200">
                    <div className="absolute inset-0 opacity-30">
                      <div className="w-full h-full" style={{
                        backgroundImage: `repeating-linear-gradient(0deg, transparent, transparent 30px, rgba(0,0,0,0.05) 30px, rgba(0,0,0,0.05) 31px),
                                         repeating-linear-gradient(90deg, transparent, transparent 30px, rgba(0,0,0,0.05) 30px, rgba(0,0,0,0.05) 31px)`
                      }} />
                    </div>
                    
                    {/* Location Badge */}
                    <motion.div
                      initial={{ opacity: 0, y: -10 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={{ delay: 0.3 }}
                      className="absolute top-4 left-4 px-4 py-2 bg-white/90 backdrop-blur-md rounded-full shadow-md"
                    >
                      <span className="font-semibold text-green-700">伦敦</span>
                    </motion.div>

                    {/* Preview Toggle */}
                    <motion.button
                      whileHover={{ scale: 1.05 }}
                      whileTap={{ scale: 0.95 }}
                      className="absolute top-4 right-4 px-4 py-2 bg-gray-700/90 backdrop-blur-md text-white rounded-full shadow-md flex items-center gap-2"
                    >
                      <Eye className="w-4 h-4" />
                      <span className="text-sm font-medium">精确</span>
                    </motion.button>

                    {/* Route Line Decoration */}
                    <motion.div
                      initial={{ pathLength: 0 }}
                      animate={{ pathLength: 1 }}
                      transition={{ delay: 0.5, duration: 1.5 }}
                      className="absolute inset-0 flex items-center justify-center"
                    >
                      <svg width="200" height="100" viewBox="0 0 200 100" className="opacity-60">
                        <motion.path
                          d="M 20 80 Q 60 20, 100 50 T 180 30"
                          fill="none"
                          stroke="#10b981"
                          strokeWidth="4"
                          strokeLinecap="round"
                          initial={{ pathLength: 0 }}
                          animate={{ pathLength: 1 }}
                          transition={{ delay: 0.5, duration: 1.5, ease: "easeInOut" }}
                        />
                      </svg>
                    </motion.div>
                  </div>

                  {/* Stats Section */}
                  <div className="p-6 grid grid-cols-3 gap-4">
                    <StatItem value="0.00" label="距离" delay={0.6} />
                    <StatItem value="0 分钟" label="时间" delay={0.7} />
                    <StatItem value="0" label="记忆" delay={0.8} />
                  </div>
                </motion.div>
              </div>

              {/* Footer Actions */}
              <div className="px-6 py-5 border-t border-gray-200 flex gap-4">
                <motion.button
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                  className="flex-1 px-6 py-4 rounded-2xl bg-gray-200 font-semibold hover:bg-gray-300 transition-colors"
                >
                  保存
                </motion.button>
                <motion.button
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                  className="flex-1 px-6 py-4 rounded-2xl bg-gradient-to-r from-amber-600 to-orange-600 text-white font-semibold shadow-lg"
                >
                  分享
                </motion.button>
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}

function StatItem({ value, label, delay }: { value: string; label: string; delay: number }) {
  return (
    <motion.div
      initial={{ y: 20, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ delay }}
      className="text-center"
    >
      <div className="text-2xl font-bold text-gray-800">{value}</div>
      <div className="text-sm text-gray-500 mt-1">{label}</div>
    </motion.div>
  );
}
