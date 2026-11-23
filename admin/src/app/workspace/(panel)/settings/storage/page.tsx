import {requireAdmin} from '@/lib/admin';
import StorageCleanup from './StorageCleanup';
export default async function StorageSettings(){await requireAdmin(true);return <><h1 className="text-2xl font-semibold">Storage setup & cleanup</h1><p className="mt-2 mb-6 text-sm text-slate-500">Bunny is prepared for configuration. Existing Supabase files remain accessible.</p><StorageCleanup/></>;}
