#!/usr/bin/env python3
"""
Builds a `voices.npz` archive that KokoroSwift's NpyzReader can load on iOS.

Downloads individual Kokoro voice packs (.pt tensors) from the official
hexgrad/Kokoro-82M repo on Hugging Face, converts each to a float32 numpy
array, and bundles them into a single .npz archive keyed as "<voice>.npy"
(matching the convention KokoroVoiceSynthesizer expects).

Run this on your Mac, then copy the resulting voices.npz to your iPhone
(AirDrop, Files app, iCloud Drive, ...) and import it from
Settings > Manage Voice Model > voices.npz > "Import from Files...".

Usage:
    pip install torch numpy huggingface_hub
    python build_voices_npz.py --output voices.npz
    python build_voices_npz.py --voices af_heart bm_george --output voices.npz
"""
import argparse

import numpy as np
import torch
from huggingface_hub import hf_hub_download

# A reasonable default set covering US/UK, male/female voices.
DEFAULT_VOICES = [
    "af_heart",
    "af_bella",
    "af_nicole",
    "af_sarah",
    "af_sky",
    "am_adam",
    "am_michael",
    "bf_emma",
    "bf_isabella",
    "bm_george",
    "bm_lewis",
]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default="hexgrad/Kokoro-82M", help="Source HF repo for voice packs")
    parser.add_argument("--voices", nargs="*", default=DEFAULT_VOICES, help="Voice names to include")
    parser.add_argument("--output", default="voices.npz", help="Output .npz path")
    args = parser.parse_args()

    arrays = {}
    for voice in args.voices:
        path = hf_hub_download(repo_id=args.repo, filename=f"voices/{voice}.pt")
        tensor = torch.load(path, map_location="cpu", weights_only=True)
        arrays[f"{voice}.npy"] = tensor.numpy().astype(np.float32)
        print(f"Added {voice}: shape {arrays[f'{voice}.npy'].shape}")

    np.savez(args.output, **arrays)
    print(f"\nWrote {args.output} with {len(arrays)} voice(s).")


if __name__ == "__main__":
    main()
