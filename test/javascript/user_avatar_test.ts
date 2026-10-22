import { expect, test } from "vitest"
import { buildUserAvatar } from "../../app/javascript/helpers/user_avatar"

test("avatars use the shared profile styles and show nickname initials without a photo", () => {
  const avatar = buildUserAvatar({ nickname: "Reader" })

  expect(avatar.className).toBe("profile-avatar profile-avatar--club_member")
  expect(avatar.getAttribute("aria-label")).toBe("Reader profile photo")
  expect(avatar.querySelector(".profile-avatar-initials")?.textContent).toBe("RE")
  expect(avatar.querySelector("img")).toBeNull()
})

test("avatars display the uploaded profile photo instead of initials", () => {
  const path = "/rails/active_storage/blobs/redirect/signed-id/avatar.jpg"
  const avatar = buildUserAvatar({ nickname: "Reader", avatar_url: path })

  expect(avatar.querySelector(".profile-avatar-image")?.getAttribute("src")).toBe(path)
  expect(avatar.querySelector(".profile-avatar-initials")).toBeNull()
})

test("avatars reject non-storage image URLs and render nickname text safely", () => {
  const avatar = buildUserAvatar({ nickname: "<img>", avatar_url: "javascript:alert(1)" })

  expect(avatar.querySelector("img")).toBeNull()
  expect(avatar.textContent).toBe("<I")
})
