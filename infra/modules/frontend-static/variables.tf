variable "name_prefix" {
  description = "Prefix for resource names (e.g. \"companybrain-phase0\")."
  type        = string
}

variable "index_document" {
  description = "Index document for the website."
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "Error document (Vite SPAs typically point this at index.html for client-side routing)."
  type        = string
  default     = "index.html"
}
