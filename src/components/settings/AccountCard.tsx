import { useState } from 'react';
import { LogOut, ShieldCheck } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { useAuth } from '@/context/AuthContext';
import { toast } from '@/hooks/use-toast';
import { api, errorMessage } from '@/lib/api/client';

/** The signed-in user's details, password change and sign out. */
export function AccountCard() {
  const { user, isOwner, signOut } = useAuth();
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [busy, setBusy] = useState(false);

  const handleChangePassword = async () => {
    setBusy(true);
    try {
      await api('POST', '/auth/change-password', { currentPassword: current, newPassword: next, client: 'web' });
      setCurrent('');
      setNext('');
      toast({ title: 'Password changed', description: 'You have been signed out of your other devices.' });
    } catch (e) {
      toast({ title: 'Password not changed', description: errorMessage(e), variant: 'destructive' });
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card className="border-border shadow-medium">
      <CardHeader>
        <CardTitle className="flex items-center gap-2 font-display">
          <ShieldCheck className="h-5 w-5 text-primary" />
          Your account
        </CardTitle>
        <CardDescription>
          {user?.name} · {user?.email} · {isOwner ? 'Owner' : 'Cashier'}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-2">
            <Label htmlFor="currentPassword">Current password</Label>
            <Input id="currentPassword" type="password" autoComplete="current-password" value={current} onChange={e => setCurrent(e.target.value)} className="h-12" />
          </div>
          <div className="space-y-2">
            <Label htmlFor="newPassword">New password</Label>
            <Input id="newPassword" type="password" autoComplete="new-password" value={next} onChange={e => setNext(e.target.value)} className="h-12" />
          </div>
        </div>
        <div className="flex flex-wrap gap-3">
          <Button onClick={handleChangePassword} disabled={busy || !current || next.length < 8} variant="outline">
            Change password
          </Button>
          <Button onClick={signOut} variant="ghost">
            <LogOut className="h-4 w-4" />
            Sign out
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
