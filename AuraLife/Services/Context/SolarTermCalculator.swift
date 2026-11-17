import Foundation

enum SolarTermCalculator {
    private static let solarTerms: [(name: String, month: Int, day: Int, guidance: String)] = [
        ("小寒", 1, 5, "阴寒极盛，宜温补脾肾、护颈避风寒"),
        ("大寒", 1, 20, "岁末天寒，饮食宜温热柔润、早睡晚起"),
        ("立春", 2, 4, "阳气初生，宜疏肝理气、少酸增甘"),
        ("雨水", 2, 19, "湿气渐升，重在健脾祛湿、忌生冷"),
        ("惊蛰", 3, 5, "春雷动阳，宜适度伸展导引、清淡养肝"),
        ("春分", 3, 20, "阴阳平分，重在作息均衡、柔和有氧"),
        ("清明", 4, 4, "肝气旺盛，忌肥甘厚腻、宜踏青舒展"),
        ("谷雨", 4, 20, "雨生百谷湿气重，重在祛湿醒脾"),
        ("立夏", 5, 5, "暑热初萌，宜清心养神、防过汗耗气"),
        ("小满", 5, 21, "湿热交加，宜清淡利湿、忌冷饮过量"),
        ("芒种", 6, 5, "湿热渐盛，宜健脾化湿、午间小憩"),
        ("夏至", 6, 21, "阳极阴生，护阳忌冰镇、适度水中运动"),
        ("小暑", 7, 7, "炎热多雨，防暑湿困脾、补充温淡茶水"),
        ("大暑", 7, 22, "湿热蒸腾，宜冬瓜薏米清化暑湿"),
        ("立秋", 8, 7, "暑湿未退秋燥初起，润燥兼顾健脾"),
        ("处暑", 8, 23, "昼暖夜凉，渐收外散之气、防受凉"),
        ("白露", 9, 7, "寒露将至，晨晚添衣、护脾胃防秋燥"),
        ("秋分", 9, 22, "燥气当令，宜温润饮食、适度抗阻"),
        ("寒露", 10, 8, "凉燥伤津，温水泡脚、忌生冷海鲜"),
        ("霜降", 10, 23, "深秋霜寒，重在暖胃护阳、固护脾肾"),
        ("立冬", 11, 7, "冬始敛藏，宜温热汤羹、早卧护阳气"),
        ("小雪", 11, 22, "寒潮渐频，室内温和导引胜过寒风出汗"),
        ("大雪", 12, 7, "仲冬阴盛，温补不过燥、睡前控水护肾"),
        ("冬至", 12, 21, "一阳来复，静养为主、温中健脾助阳生")
    ]

    static func term(for date: Date) -> (name: String, guidance: String) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.month, .day], from: date)
        let month = components.month ?? 1
        let day = components.day ?? 1
        let mmdd = month * 100 + day

        var current = solarTerms.last!
        for term in solarTerms {
            let termMMDD = term.month * 100 + term.day
            if mmdd >= termMMDD {
                current = term
            }
        }
        return (current.name, current.guidance)
    }
}
