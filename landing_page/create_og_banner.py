import os
import arabic_reshaper
from bidi.algorithm import get_display
from PIL import Image, ImageDraw, ImageFilter, ImageFont

def create_og_banner():
    # 1. Canvas Dimensions (Standard Open Graph 1200 x 630)
    WIDTH, HEIGHT = 1200, 630
    
    # Base Emerald Background
    banner = Image.new("RGBA", (WIDTH, HEIGHT), (7, 13, 9, 255))
    
    # 2. Subtle Radial Glow (Warm Gold & Emerald ambience)
    glow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    
    center_x, center_y = 860, 315
    for r in range(480, 0, -20):
        alpha = int(35 * (1 - r / 480))
        glow_draw.ellipse(
            (center_x - r, center_y - r, center_x + r, center_y + r),
            fill=(195, 154, 63, alpha)
        )
    banner = Image.alpha_composite(banner, glow)

    # 3. Load Authentic Screenshot (Fatiha / Quran recitation)
    screenshot_path = r"d:\there is no god unless ALLAH\Playstore\Natlu\landing_page\assets\fatiha.png"
    if not os.path.exists(screenshot_path):
        screenshot_path = r"d:\there is no god unless ALLAH\Playstore\Natlu\landing_page\assets\qamar.png"
    
    screen_img = Image.open(screenshot_path).convert("RGBA")
    
    phone_w = 260
    phone_h = int(phone_w * (screen_img.height / screen_img.width))
    if phone_h > 550:
        phone_h = 550
        phone_w = int(phone_h * (screen_img.width / screen_img.height))
        
    screen_resized = screen_img.resize((phone_w, phone_h), Image.Resampling.LANCZOS)
    
    # Screen mask with rounded corners
    screen_mask = Image.new("L", (phone_w, phone_h), 0)
    mask_draw = ImageDraw.Draw(screen_mask)
    mask_draw.rounded_rectangle((0, 0, phone_w, phone_h), radius=28, fill=255)
    screen_resized.putalpha(screen_mask)
    
    # Phone Hardware Bezel
    bezel_padding = 7
    bezel_w = phone_w + (bezel_padding * 2)
    bezel_h = phone_h + (bezel_padding * 2)
    bezel_x = 810
    bezel_y = (HEIGHT - bezel_h) // 2
    
    # Drop shadow behind phone
    shadow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow)
    s_draw.rounded_rectangle(
        (bezel_x - 12, bezel_y + 12, bezel_x + bezel_w + 12, bezel_y + bezel_h + 24),
        radius=36,
        fill=(0, 0, 0, 190)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(20))
    banner = Image.alpha_composite(banner, shadow)
    
    # Bezel Frame
    hardware = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    h_draw = ImageDraw.Draw(hardware)
    h_draw.rounded_rectangle(
        (bezel_x, bezel_y, bezel_x + bezel_w, bezel_y + bezel_h),
        radius=34,
        fill=(10, 18, 13, 255),
        outline=(195, 154, 63, 140),
        width=2
    )
    banner = Image.alpha_composite(banner, hardware)
    banner.paste(screen_resized, (bezel_x + bezel_padding, bezel_y + bezel_padding), screen_resized)

    # 4. App Logo + App Name SIDE-BY-SIDE
    icon_path = r"d:\there is no god unless ALLAH\Playstore\Natlu\landing_page\app_icon.png"
    icon_x, icon_y = 90, 80
    icon_size = 94

    if os.path.exists(icon_path):
        icon_img = Image.open(icon_path).convert("RGBA")
        icon_resized = icon_img.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
        
        icon_mask = Image.new("L", (icon_size, icon_size), 0)
        im_draw = ImageDraw.Draw(icon_mask)
        im_draw.rounded_rectangle((0, 0, icon_size, icon_size), radius=22, fill=255)
        icon_resized.putalpha(icon_mask)
        
        # Icon Shadow
        icon_shadow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
        is_draw = ImageDraw.Draw(icon_shadow)
        is_draw.rounded_rectangle(
            (icon_x - 4, icon_y + 4, icon_x + icon_size + 4, icon_y + icon_size + 12),
            radius=24,
            fill=(0, 0, 0, 150)
        )
        icon_shadow = icon_shadow.filter(ImageFilter.GaussianBlur(8))
        banner = Image.alpha_composite(banner, icon_shadow)
        banner.paste(icon_resized, (icon_x, icon_y), icon_resized)
        
        draw = ImageDraw.Draw(banner)
        draw.rounded_rectangle(
            (icon_x, icon_y, icon_x + icon_size, icon_y + icon_size),
            radius=22,
            outline=(195, 154, 63, 180),
            width=2
        )

    # 5. Arabic & English Typography (Placed right beside the logo)
    name_x = icon_x + icon_size + 24
    
    # Reshape Arabic text correctly
    arabic_raw = "اتلو القرآن"
    reshaped_ar = arabic_reshaper.reshape(arabic_raw)
    bidi_ar = get_display(reshaped_ar)
    
    font_title_ar = ImageFont.truetype(r"C:\Windows\Fonts\majallab.ttf", 52)
    font_title_en = ImageFont.truetype(r"C:\Windows\Fonts\arialbd.ttf", 32)
    font_desc = ImageFont.truetype(r"C:\Windows\Fonts\arial.ttf", 22)
    font_badge = ImageFont.truetype(r"C:\Windows\Fonts\arialbd.ttf", 18)

    draw = ImageDraw.Draw(banner)
    # Arabic Title
    draw.text((name_x, icon_y + 2), bidi_ar, fill=(214, 175, 85, 255), font=font_title_ar)
    # English Title
    draw.text((name_x, icon_y + 54), "Recite Quran", fill=(236, 229, 216, 255), font=font_title_en)

    # Golden Divider Line
    line_y = icon_y + icon_size + 35
    draw.line((icon_x, line_y, icon_x + 640, line_y), fill=(195, 154, 63, 130), width=2)

    # Features / Bullets
    desc_lines = [
        "• Real-Time Speech Recognition & Recitation Tutor",
        "• Instant Tajweed Feedback & Word Highlighting",
        "• 100% Free • Ad-Free • Multi-Platform"
    ]
    
    y_offset = line_y + 35
    for line in desc_lines:
        draw.text((icon_x, y_offset), line, fill=(181, 175, 159, 255), font=font_desc)
        y_offset += 42

    # Platform Badges
    badges = ["Android", "iOS", "Web App"]
    bx = icon_x
    by = 480
    for b in badges:
        bw = len(b) * 11 + 32
        draw.rounded_rectangle((bx, by, bx + bw, by + 36), radius=8, fill=(17, 29, 22, 230), outline=(195, 154, 63, 90), width=1)
        draw.text((bx + 16, by + 8), b, fill=(214, 175, 85, 255), font=font_badge)
        bx += bw + 14

    # Save to landing_page/assets/og-preview.png
    output_dir = r"d:\there is no god unless ALLAH\Playstore\Natlu\landing_page\assets"
    os.makedirs(output_dir, exist_ok=True)
    out_path = os.path.join(output_dir, "og-preview.png")
    banner.convert("RGB").save(out_path, "PNG", optimize=True)
    print("SUCCESS")

if __name__ == "__main__":
    create_og_banner()
