import sherpa_onnx
import miniaudio
import urllib.request
import json
import sys
import os
import random

# ==========================================
# TEST CONFIGURATION
# ==========================================
# Set to True to inject static/hiss into the studio MP3s to simulate a cheap Android microphone
SIMULATE_BAD_MIC = True
# 0.01 = Light static, 0.05 = Noticeable hiss, 0.10 = Bad noisy room
NOISE_LEVEL = 0.03 
# ==========================================

def download_audio(url, output_path):
    try:
        urllib.request.urlretrieve(url, output_path)
        return True
    except Exception as e:
        print(f"Failed to download {url}: {e}")
        return False

def main():
    # Define the Reciters (Qaris) you want to test
    qaris = [
        {"id": "Alafasy_128kbps", "name": "Alafasy"},
        {"id": "Husary_128kbps", "name": "Husary"},
        {"id": "Minshawy_Murattal_128kbps", "name": "Minshawy"},
        # You can find more Qari IDs on everyayah.com
    ]
    
    # Define the Surahs/Ayahs you want to test
    surahs_to_test = [
        {"name": "Al-Fatiha", "surah": 1, "start_ayah": 1, "end_ayah": 7},
        {"name": "Al-Ikhlas", "surah": 112, "start_ayah": 1, "end_ayah": 4},
        {"name": "Al-Falaq", "surah": 113, "start_ayah": 1, "end_ayah": 5},
        {"name": "An-Nas", "surah": 114, "start_ayah": 1, "end_ayah": 6},
        # Example of a large surah test (first 10 ayahs):
        # {"name": "Al-Baqarah", "surah": 2, "start_ayah": 1, "end_ayah": 10},
    ]

    # Generate the cartesian product of all Qaris x Surahs
    scenarios = []
    for qari in qaris:
        for surah in surahs_to_test:
            scenario = surah.copy()
            scenario["name"] = f"{surah['name']} ({qari['name']})"
            scenario["qari_id"] = qari["id"]
            scenario["qari_name"] = qari["name"]
            scenarios.append(scenario)
    
    # Setup Sherpa
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    model_path = os.path.join(base_dir, "assets", "model", "zipformer_p_arabic_v2.int8.onnx")
    tokens_path = os.path.join(base_dir, "assets", "model", "tokens.txt")
    
    print(f"Loading Sherpa-ONNX model...")
    recognizer = sherpa_onnx.OnlineRecognizer.from_zipformer2_ctc(
        model=model_path,
        tokens=tokens_path,
        num_threads=1
    )
    
    results_list = []
    chunk_size = 1600 # 100ms
    
    for scenario in scenarios:
        print(f"\n=============================================")
        print(f"Processing True Streaming Scenario: {scenario['name']} ({scenario['surah']}:{scenario['start_ayah']}-{scenario['end_ayah']})")
        print(f"=============================================")
        
        all_samples = []
        
        for ayah in range(scenario['start_ayah'], scenario['end_ayah'] + 1):
            url = f"https://everyayah.com/data/{scenario['qari_id']}/{scenario['surah']:03d}{ayah:03d}.mp3"
            temp_path = f"temp_batch_stream_{scenario['qari_name']}_{scenario['surah']:03d}{ayah:03d}.mp3"
            
            print(f"  Downloading Ayah {ayah}...")
            if download_audio(url, temp_path):
                try:
                    decoded = miniaudio.decode_file(temp_path, sample_rate=16000, output_format=miniaudio.SampleFormat.FLOAT32, nchannels=1)
                    all_samples.extend(list(decoded.samples))
                except Exception as e:
                    print(f"  Error decoding audio {temp_path}: {e}")
                finally:
                    if os.path.exists(temp_path):
                        os.remove(temp_path)
        
        if not all_samples:
            print(f"Skipping {scenario['name']} due to download failures.")
            continue
            
        print(f"  Running 100ms Frame Simulation...")
        stream = recognizer.create_stream()
        frames = []
        
        for i in range(0, len(all_samples), chunk_size):
            chunk = all_samples[i:i+chunk_size]
            
            # Inject Microphone Static/Noise if configured
            if SIMULATE_BAD_MIC:
                noisy_chunk = [s + random.gauss(0, NOISE_LEVEL) for s in chunk]
                # Clamp values to valid float32 audio range [-1.0, 1.0] to prevent distortion crashing
                chunk = [max(-1.0, min(1.0, s)) for s in noisy_chunk]
                
            # Feed chunk
            stream.accept_waveform(16000, chunk)
            
            # Decode what is available
            while recognizer.is_ready(stream):
                recognizer.decode_stream(stream)
                
            # Get the partial result at this exact millisecond
            result = recognizer.get_result(stream)
            text = getattr(result, "text", "")
            if not text:
                 text = str(result).strip()
            
            # Only save frames that have some text to avoid massive empty JSON
            if text:
                frames.append({
                    "frame_index": len(frames),
                    "text": text
                })
            
        stream.input_finished()
        while recognizer.is_ready(stream):
            recognizer.decode_stream(stream)
            
        final_result = recognizer.get_result(stream)
        final_text = getattr(final_result, "text", "")
        if not final_text:
             final_text = str(final_result).strip()
        frames.append({
            "frame_index": len(frames),
            "text": final_text
        })
            
        results_list.append({
            "name": scenario["name"],
            "qari": scenario["qari_name"],
            "surah": scenario["surah"],
            "start_ayah": scenario["start_ayah"],
            "end_ayah": scenario["end_ayah"],
            "frames": frames
        })
        
        print(f"  Completed {scenario['name']}. Saved {len(frames)} frames.")
    
    out_file = os.path.join(os.path.dirname(__file__), "batch_streaming_test_data.json")
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(results_list, f, ensure_ascii=False, indent=2)
        
    print(f"\nSaved all Batch True Streaming outputs to {out_file}")

if __name__ == "__main__":
    main()
