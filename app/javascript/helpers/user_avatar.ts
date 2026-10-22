export function buildUserAvatar(author: { nickname: string; avatar_url?: string | null }): HTMLElement {
  const avatar = document.createElement("div")
  avatar.className = "profile-avatar profile-avatar--club_member"
  avatar.setAttribute("role", "img")
  avatar.setAttribute("aria-label", `${author.nickname} profile photo`)

  if (author.avatar_url?.startsWith("/rails/active_storage/")) {
    const image = document.createElement("img")
    image.className = "profile-avatar-image"
    image.src = author.avatar_url
    image.alt = ""
    image.setAttribute("aria-hidden", "true")
    avatar.append(image)
  } else {
    const initials = document.createElement("span")
    initials.className = "profile-avatar-initials"
    initials.setAttribute("aria-hidden", "true")
    initials.textContent = author.nickname.slice(0, 2).toUpperCase()
    avatar.append(initials)
  }

  return avatar
}
