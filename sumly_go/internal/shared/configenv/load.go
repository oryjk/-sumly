package configenv

import "github.com/joho/godotenv"

// Load reads local development variables without overriding exported values.
func Load() {
	_ = godotenv.Load()
}
