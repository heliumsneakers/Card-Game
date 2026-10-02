import { createContext } from "react";
import type { CardDefinition } from "./model";

// Shared catalog metadata belongs outside any individual form component.
export type AuthoringCard = Pick<CardDefinition, "id" | "name" | "element" | "type">;
export const AuthoringCards = createContext<AuthoringCard[]>([]);
