import SwiftUI

enum AboutUsContent {
    struct Section: Equatable {
        let title: String
        let paragraphs: [String]
    }

    static let title = "关于我们"
    static let location = "伦敦"

    static let sections: [Section] = [
        Section(
            title: "",
            paragraphs: [
                "Worldo是我独立开发的第二款产品，没有什么灵光一闪的时刻，没有什么激动人心组建团队大干一场的氛围，我只是想到了，然后就开始做了，或许别的个人开发者也是这样。但我依然应该为这个产品写点什么，关于为什么是Worldo。\n\n满足“我”而不是想象的用户。互联网产品喜欢聊需求，聊用户，用户喜欢这个，不喜欢那个，用户如何被讨好，被引导。但当我不是一个资本家，我还应该带着这样的心去做产品吗？在无数失去信心的时候，我只是提醒自己我需要无限逼近我，那我也会是很多人，于是所有的需求都变得一样重要。",
                "那我喜欢什么。我喜欢散步，我在很多地方走来走去，拍一些照片，做一点记录。这个市面上有很多高精运动软件，数字让我们产生对生活的掌控感，数字也让我们焦虑。如果我不是一个跑者，我只是在一个城市， 又到了另一个城市，我路过了一个公园，在夜路上遇到一只狐狸，在一家咖啡店呆了一下午，城市里，城市间，这样的东西应该如何被悄无声息得记录下来。数字本身是没有美感的，线条或许是有美满的，记忆是真正重要的，带着这样的想法，我脑中几乎立刻有了Worldo应有的样子。我们的照片，文字，和一段段旅程轨迹如何被一个载体所容纳，装帧，而不是散落在过去。GoogleMap可以实现一些工具性的作用，我想实现互补的一面。",
                "其次我喜欢游戏化的概念，我时常期望自己能够喜欢游戏，仿佛这样生活会更简单一点。但实际上我也并不玩游戏，我只是在想象中觉得种花采蘑菇去朋友家窜门换装都很有意思，但这也只不过是我对生活的一种期待投射。我希望Worldo能满足我这样的期待，记录下我家到朋友家的路径，我装扮成怎样出门，我买了一盆植物，朋友收养了一只猫的故事，worldo理应存在于二点五次元，我如何为我的线下生活丰荣，都应该同时获得线下线上双份的满足感，从而我更愿意认真得对待我的生活。worldo今天除了最核心的世界轨迹城市记忆收集的功能以外，用到了像素小人，只是因为我和朋友们都很喜欢很萌的元素。我们为它配置了各种装备，也特地做了社交功能，我希望即使我和朋友在不同城市，但我可以去好友的主页坐一坐，看看他们最近的旅程。在未来我还会不遗余力加入任何我想要的元素，例如和好友一起的旅行可以出现在一个电子地图，收藏别人的记忆，地图会配合天气下雨，但你也可以去买一把雨伞，等等等等。",
                "最后，AI时代app已死，这是我在整个开发过程中时常刷到的，每次都激起我的一阵恐慌，那我做的事情还有意义吗，我所消耗的精力值得吗？也许在科技巨头眼里都是没有意义的，我也思考如果什么都被ai化了，我们到底可以留下什么。我想到了我很喜欢的一些物件，ccd，胶片机，cd机，ipod，因为音乐，照片的永恒实现了古早载体的迷人，而我同时喜欢着作品和创造作品的工具，worldo会是一个开始。"
            ]
        ),
        Section(
            title: L10n.t("about_postscript"),
            paragraphs: [
                "旅行者的需求"
            ]
        ),
        Section(
            title: "旅行者的需求",
            paragraphs: [
                "Worldo里我最喜欢的板块是很简单的Journey Memory，也就是最后旅程被归档的图文所呈现的形态。我认为做APP会时常感到气馁的点是它并没有那么像创作，也并不像是一个人的游戏，决定成功的因素绝不仅仅是产品本身，同时一款产品的产生却会有成千上万的竞品随之而来，那为什么是我。想到最后我觉得可以回到我为什么依然喜欢一个最简单的记录功能。我觉得新其实更多时候只是既有东西的组合，组合好了就会达成某种和谐，这种和谐会产生一些能量。也就是说它实现了我个人最核心的需求，旅行者的需求，后来在火车上飞机上我都自然开始写点东西，拍点东西，就像是一种图文和时空和谐的归位，我觉得什么都对了。初版Worldo被测试的时候我在济州岛，爬汉拿山那天我用它记录了一路的旅程，后来我也经常和朋友炫耀导出的游记，这世界还存在游记吗？"
            ]
        ),
        Section(
            title: "赛博遛狗的故事",
            paragraphs: [
                "一个朋友打算在装备里画了一只小狗，因为她想到她的小狗安迪以后死了，她散步的时候可以看到地图里自己带着赛博小狗一起，然后还没画她就痛哭一场。很萌，我想要做的就是这种很萌的东西。又有一天我在为生活的一切，为这款app焦虑的时候，骑着车记录着轨迹，我突然觉得没关系，即使最后是自娱自乐也没关系。我为朋友们建造了一个赛博空间，这个空间只有30个人也是另一种伟大的故事。"
            ]
        )
    ]
}

struct AboutUsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headerBlock

                divider
                    .padding(.vertical, 28)

                articleBody
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(FigmaTheme.mutedBackground.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            UnifiedNavigationHeader(
                chrome: NavigationChrome(
                    title: AboutUsContent.title,
                    leadingAccessory: .back,
                    titleLevel: .secondary
                ),
                horizontalPadding: 18,
                topPadding: 8,
                bottomPadding: 12,
                onLeadingTap: { dismiss() }
            ) {
                Color.clear
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ABOUT WORLDO")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.8)
                .foregroundColor(Color.black.opacity(0.48))

            VStack(alignment: .leading, spacing: 8) {
                Text(AboutUsContent.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(UITheme.softBlack)

                Text(AboutUsContent.location)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.26, green: 0.30, blue: 0.35))

                Text("Journey Memory")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(1.2)
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.51))
            }

            HStack(spacing: 10) {
                metaChip(icon: "location", text: AboutUsContent.location)
                metaChip(icon: "text.book.closed", text: "Worldo")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var articleBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(AboutUsContent.sections.enumerated()), id: \.offset) { index, section in
                if index == 0 {
                    bodyParagraphGroup(section.paragraphs)
                } else if section.title == L10n.t("about_postscript") {
                    asideSection
                        .padding(.top, 48)
                }
            }
        }
    }

    private var asideSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.key("about_postscript"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(UITheme.softBlack)

            ForEach(Array(AboutUsContent.sections.dropFirst(2).enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 10) {
                    if !section.title.isEmpty {
                        Text(section.title)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Color(red: 0.26, green: 0.30, blue: 0.35))
                            .padding(.top, section.title == "旅行者的需求" ? 6 : 0)
                    }

                    bodyParagraphGroup(section.paragraphs)
                }
                .padding(.bottom, 14)
            }
        }
    }

    private func bodyParagraphGroup(_ paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color(red: 0.21, green: 0.26, blue: 0.32))
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.12))
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))

            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(Color.black.opacity(0.68))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.black.opacity(0.05))
        .clipShape(Capsule())
    }
}
