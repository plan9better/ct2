import ctranslate2

def main():
    converter = ctranslate2.converters.TransformersConverter("model/")
    converter.convert("ct2_model")
    print("Hello from ct2!")


if __name__ == "__main__":
    main()
