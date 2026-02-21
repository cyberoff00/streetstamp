import { motion, AnimatePresence } from "motion/react";
import { X, Minimize2, Camera, Image, ToggleLeft } from "lucide-react";
import { useState } from "react";

export function AddMemoryModal({
  isOpen,
  onClose,
}: {
  isOpen: boolean;
  onClose: () => void;
}) {
  const [memoryText, setMemoryText] = useState("");
  const [selfieMode, setSelfieMode] = useState(false);

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
            <div className="bg-gradient-to-br from-white to-gray-50 rounded-3xl shadow-2xl overflow-hidden h-full flex flex-col">
              {/* Header */}
              <div className="px-6 py-5 flex items-center justify-between border-b border-gray-200">
                <h3 className="text-2xl font-semibold">添加回忆</h3>
                <div className="flex items-center gap-2">
                  <motion.button
                    whileHover={{ scale: 1.1, rotate: 90 }}
                    whileTap={{ scale: 0.9 }}
                    onClick={onClose}
                    className="p-2 hover:bg-gray-100 rounded-full transition-colors"
                  >
                    <Minimize2 className="w-5 h-5" />
                  </motion.button>
                  <motion.button
                    whileHover={{ scale: 1.1, rotate: 90 }}
                    whileTap={{ scale: 0.9 }}
                    onClick={onClose}
                    className="p-2 hover:bg-gray-100 rounded-full transition-colors"
                  >
                    <X className="w-5 h-5" />
                  </motion.button>
                </div>
              </div>

              {/* Content */}
              <div className="flex-1 p-6 overflow-y-auto">
                <textarea
                  value={memoryText}
                  onChange={(e) => setMemoryText(e.target.value)}
                  placeholder="在这里写下你的回忆..."
                  className="w-full h-64 px-4 py-3 bg-white rounded-2xl border-2 border-gray-200 focus:border-amber-500 focus:outline-none resize-none text-gray-700 placeholder-gray-400 transition-colors"
                />

                {/* Media Options */}
                <div className="mt-6 flex items-center gap-4">
                  <motion.button
                    whileHover={{ scale: 1.05 }}
                    whileTap={{ scale: 0.95 }}
                    className="w-16 h-16 rounded-2xl bg-black text-white flex items-center justify-center shadow-lg"
                  >
                    <Camera className="w-7 h-7" />
                  </motion.button>

                  <motion.button
                    whileHover={{ scale: 1.05 }}
                    whileTap={{ scale: 0.95 }}
                    className="w-16 h-16 rounded-2xl bg-gray-700 text-white flex items-center justify-center shadow-lg"
                  >
                    <Image className="w-7 h-7" />
                  </motion.button>

                  <div className="flex-1" />

                  <div className="flex items-center gap-3">
                    <span className="text-sm text-gray-600">自拍镜像</span>
                    <motion.button
                      whileTap={{ scale: 0.9 }}
                      onClick={() => setSelfieMode(!selfieMode)}
                      className={`w-14 h-8 rounded-full transition-colors ${
                        selfieMode ? "bg-amber-500" : "bg-gray-300"
                      } relative`}
                    >
                      <motion.div
                        animate={{ x: selfieMode ? 24 : 0 }}
                        transition={{ type: "spring", stiffness: 500, damping: 30 }}
                        className="absolute top-1 left-1 w-6 h-6 bg-white rounded-full shadow-md"
                      />
                    </motion.button>
                  </div>
                </div>
              </div>

              {/* Footer Actions */}
              <div className="px-6 py-5 border-t border-gray-200 flex gap-4">
                <motion.button
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                  onClick={onClose}
                  className="flex-1 px-6 py-4 rounded-2xl border-2 border-gray-300 font-semibold hover:bg-gray-50 transition-colors"
                >
                  取消
                </motion.button>
                <motion.button
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                  className="flex-1 px-6 py-4 rounded-2xl bg-gradient-to-r from-amber-600 to-orange-600 text-white font-semibold shadow-lg"
                >
                  保存
                </motion.button>
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}
