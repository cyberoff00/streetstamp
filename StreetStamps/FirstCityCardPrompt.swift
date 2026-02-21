//
//  FirstCityCardPrompt.swift
//  StreetStamps
//
//  Created by Claire Yang on 13/01/2026.
//

import SwiftUI

struct FirstCityCardPrompt: View {
    var onGenerate: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(L10n.key("first_city_prompt_title"))
                .font(.system(size: 18, weight: .semibold))

            Text(L10n.key("first_city_prompt_desc"))
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Button(L10n.t("later")) { onSkip() }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(10)

                Button(L10n.t("first_city_prompt_generate")) { onGenerate() }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .padding(.top, 24)
        .presentationDetents([.height(280)])
    }
}
