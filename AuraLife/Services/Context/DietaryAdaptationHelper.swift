import Foundation

struct DietaryConstraints: Sendable {
    let avoidSeafood: Bool
    let vegetarian: Bool
    let avoidDairy: Bool
    let avoidEgg: Bool
    let avoidRedMeat: Bool
    let avoidSpicyOrGinger: Bool

    init(preferences: [String]) {
        let joined = preferences.joined(separator: " ")
        self.avoidSeafood = joined.contains("海鲜") || joined.contains("虾") || joined.contains("鱼") || joined.contains("蟹")
        self.vegetarian = joined.contains("素食")
        self.avoidDairy = joined.contains("乳") || joined.contains("奶")
        self.avoidEgg = joined.contains("忌蛋") || joined.contains("鸡蛋过敏")
        self.avoidRedMeat = joined.contains("牛羊") || joined.contains("红肉") || joined.contains("不吃肉")
        self.avoidSpicyOrGinger = joined.contains("忌姜") || joined.contains("忌葱蒜")
    }
}

enum DietaryAdaptationHelper {
    static func adaptCard(
        title: String,
        detail: String,
        reasoning: String,
        timeSlot: String,
        diningEnvironment: String,
        dietaryPreferences: [String]
    ) -> (title: String, detail: String, reasoning: String) {
        let constraints = DietaryConstraints(preferences: dietaryPreferences)
        var newTitle = title
        var newDetail = detail
        let newReasoning = reasoning

        // 1. 外卖 / 食堂真实可执行方案改写（严禁要求现炖 40 分钟或开火炒药材）
        if diningEnvironment == "外卖" || diningEnvironment == "食堂" {
            let envLabel = diningEnvironment
            if timeSlot.contains("07:") || timeSlot.contains("08:") || timeSlot.contains("09:") {
                if newTitle.contains("焦米") || newTitle.contains("温胃") || newTitle.contains("姜") {
                    newTitle = "小米南瓜粥配水煮蛋 + 餐后冲泡陈皮姜茶包"
                    newDetail = "\(envLabel)/便利店点温热小米粥 + 水煮蛋 1 个；餐后半小时用办公室热水冲泡独立陈皮姜茶包，忌空腹猛灌。"
                } else if newTitle.contains("荷叶") || newTitle.contains("淡饮") {
                    newTitle = "温热燕麦杂粮粥 + 水煮蛋 · 餐后荷叶薏米茶包"
                    newDetail = "\(envLabel)/便利店选温热杂粮粥配鸡蛋；餐后用独立炒薏米荷叶茶包热水冲泡，不去加糖或冰镇。"
                } else if newTitle.contains("黄芪") || newTitle.contains("红枣") || newTitle.contains("茯苓") || newTitle.contains("白术") {
                    newTitle = "热豆浆/小米粥配蒸蛋 + 餐后健脾代茶包"
                    newDetail = "\(envLabel)买温热小米粥或无糖热豆浆配蛋类先垫胃，餐后热水冲泡茯苓陈皮独立茶包。"
                }
            } else if timeSlot.contains("12:") || timeSlot.contains("13:") {
                if newTitle.contains("炖") || newTitle.contains("冬瓜薏米瘦肉") || newTitle.contains("芡实") || newTitle.contains("清蒸鲈鱼") {
                    newTitle = envLabel == "外卖"
                        ? "清汤鸡丝米粉 / 去皮白切鸡饭（备注少油免辣）"
                        : "食堂清蒸蛋白 + 白灼时蔬 + 半碗杂粮饭"
                    newDetail = envLabel == "外卖"
                        ? "外卖选清汤非油炸主食或去皮白切鸡饭，备注「少油少盐免辣、不要冰饮」，油多菜品先用热汤涮去浮油。"
                        : "食堂打菜优先清蒸/白灼菜式配半碗米饭，避开红烧油炸与冰饮，七分饱停筷。"
                } else if newTitle.contains("暖胃粥") || newTitle.contains("小米") {
                    newTitle = "温热山药瘦肉粥 / 鸡丝汤面（备注免辣少油）"
                    newDetail = "\(envLabel)点软烂热汤面或山药瘦肉粥，备注「不放辣椒花椒、少油温热」，避开生冷凉菜。"
                }
            } else if timeSlot.contains("18:") || timeSlot.contains("19:") {
                if newTitle.contains("汤") || newTitle.contains("蒸蛋") || newTitle.contains("虾仁") {
                    newTitle = envLabel == "外卖"
                        ? "菌菇豆腐鸡丝汤 / 轻食温热鸡肉碗（少主食）"
                        : "食堂豆腐蔬菜汤 + 清蒸蛋白（少油少主食）"
                    newDetail = "\(envLabel)晚餐选清汤高蛋白配绿叶菜，主食减半或换成一小块蒸南瓜，19:30 前吃完。"
                }
            }
        }

        // 2. 忌口绝对禁止与食材安全替换
        if constraints.vegetarian {
            newTitle = replaceProteinTokens(
                in: newTitle,
                targets: ["瘦肉", "鸡胸肉", "鸡丝", "鸡腿", "排骨", "白切鸡", "鲜虾", "虾仁", "鲈鱼", "鱼虾", "鱼"],
                replacement: "嫩豆腐菌菇"
            )
            newDetail = replaceProteinTokens(
                in: newDetail,
                targets: ["瘦肉片 120g", "瘦肉 150g", "瘦肉 120g", "瘦肉丝 60g", "瘦肉片 80g", "清蒸鸡胸肉 100g", "鸡胸肉", "鸡丝", "去皮白切鸡饭", "白切鸡", "虾仁 100g", "虾仁 80g", "鲜虾", "鲈鱼 180g", "鲈鱼 160g", "鱼虾 150g", "鲈鱼", "鱼虾", "排骨", "瘦肉"],
                replacement: "嫩豆腐与香菇菌菇 150g"
            )
            if constraints.avoidEgg {
                newTitle = replaceProteinTokens(in: newTitle, targets: ["水煮蛋", "蒸蛋", "滑蛋", "鸡蛋"], replacement: "无糖热豆浆")
                newDetail = replaceProteinTokens(in: newDetail, targets: ["水煮蛋 1 个", "水煮蛋", "蒸滑蛋", "鸡蛋 2 个", "蛋类", "鸡蛋"], replacement: "温热豆制品或无糖豆浆")
            }
        } else {
            if constraints.avoidSeafood {
                newTitle = replaceProteinTokens(in: newTitle, targets: ["清蒸鲜虾", "清蒸鲈鱼", "虾仁", "鲜虾", "鲈鱼", "海带", "鱼虾"], replacement: "去皮鸡胸/嫩豆腐")
                newDetail = replaceProteinTokens(in: newDetail, targets: ["清蒸鱼虾 150g", "虾仁 100g", "虾仁 80g", "鲈鱼 180g", "鲈鱼", "虾仁", "鲜虾", "海带"], replacement: "去皮鸡胸肉或嫩豆腐")
            }
            if constraints.avoidRedMeat {
                newTitle = replaceProteinTokens(in: newTitle, targets: ["瘦肉", "排骨", "牛肉", "羊肉"], replacement: "去皮鸡胸肉")
                newDetail = replaceProteinTokens(in: newDetail, targets: ["瘦肉片 120g", "瘦肉 150g", "瘦肉 120g", "瘦肉丝 60g", "瘦肉片 80g", "排骨", "瘦肉"], replacement: "鸡胸肉或嫩豆腐")
            }
            if constraints.avoidEgg {
                newTitle = replaceProteinTokens(in: newTitle, targets: ["蒸滑蛋", "蒸蛋", "水煮蛋", "鸡蛋"], replacement: "嫩豆腐")
                newDetail = replaceProteinTokens(in: newDetail, targets: ["水煮蛋 1 个", "水煮蛋", "鸡蛋 2 个", "蒸滑蛋", "蛋虾", "蛋类"], replacement: "嫩豆腐或去皮鸡丝")
            }
        }

        if constraints.avoidDairy {
            newTitle = newTitle.replacingOccurrences(of: "牛奶", with: "温热无糖豆浆")
            newDetail = newDetail.replacingOccurrences(of: "牛奶", with: "温热无糖豆浆")
        }

        if constraints.avoidSpicyOrGinger {
            newTitle = newTitle.replacingOccurrences(of: "生姜", with: "陈皮")
            newTitle = newTitle.replacingOccurrences(of: "姜丝", with: "陈皮丝")
            newDetail = newDetail.replacingOccurrences(of: "老姜 2 片 + ", with: "干山药片 10g + ")
            newDetail = newDetail.replacingOccurrences(of: "老姜 1 片 + ", with: "干山药片 8g + ")
            newDetail = newDetail.replacingOccurrences(of: "生姜 2 片、", with: "茯苓 5g、")
            newDetail = newDetail.replacingOccurrences(of: "姜丝", with: "少许陈皮丝")
            newDetail = newDetail.replacingOccurrences(of: "姜葱", with: "少许陈皮")
        }

        return (newTitle, newDetail, newReasoning)
    }

    static func adaptPayload(
        _ payload: AIPlannedCardPayload,
        diningEnvironment: String,
        dietaryPreferences: [String]
    ) -> AIPlannedCardPayload {
        guard payload.resolvedCategory == .diet else { return payload }
        let adapted = adaptCard(
            title: payload.title,
            detail: payload.actionDetail,
            reasoning: payload.reasoning,
            timeSlot: payload.timeSlot,
            diningEnvironment: diningEnvironment,
            dietaryPreferences: dietaryPreferences
        )
        return AIPlannedCardPayload(
            category: payload.category,
            timeSlot: payload.timeSlot,
            title: adapted.title,
            actionDetail: adapted.detail,
            reasoning: adapted.reasoning
        )
    }

    private static func replaceProteinTokens(
        in text: String,
        targets: [String],
        replacement: String
    ) -> String {
        var result = text
        for target in targets where result.contains(target) {
            result = result.replacingOccurrences(of: target, with: replacement)
        }
        return result
    }
}
