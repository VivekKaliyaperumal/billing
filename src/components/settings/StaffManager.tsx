import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { KeyRound, Loader2, Plus, Trash2, UserCog } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Switch } from '@/components/ui/switch';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useAuth } from '@/context/AuthContext';
import { toast } from '@/hooks/use-toast';
import { api, errorMessage } from '@/lib/api/client';
import { Role, StaffMember } from '@/lib/api/types';

const STAFF_KEY = ['staff'];

/** Owner only: add cashiers, change roles, reset passwords, disable or remove staff. */
export function StaffManager() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const { data: staff = [], isLoading } = useQuery({
    queryKey: STAFF_KEY,
    queryFn: () => api<StaffMember[]>('GET', '/staff'),
  });
  const [isAddOpen, setIsAddOpen] = useState(false);
  const [resetFor, setResetFor] = useState<StaffMember | null>(null);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [role, setRole] = useState<Role>('cashier');
  const [busy, setBusy] = useState(false);

  const run = async (action: () => Promise<unknown>, success: string) => {
    setBusy(true);
    try {
      await action();
      await queryClient.invalidateQueries({ queryKey: STAFF_KEY });
      toast({ title: success });
      return true;
    } catch (e) {
      toast({ title: 'Could not update staff', description: errorMessage(e), variant: 'destructive' });
      return false;
    } finally {
      setBusy(false);
    }
  };

  const handleAdd = async () => {
    const ok = await run(
      () => api('POST', '/staff', { name: name.trim(), email: email.trim(), password, role }),
      `${name.trim()} can now sign in`,
    );
    if (ok) {
      setIsAddOpen(false);
      setName('');
      setEmail('');
      setPassword('');
      setRole('cashier');
    }
  };

  const handleReset = async () => {
    if (!resetFor) return;
    const ok = await run(() => api('PATCH', `/staff/${resetFor.id}`, { password }), `Password reset for ${resetFor.name}`);
    if (ok) {
      setResetFor(null);
      setPassword('');
    }
  };

  return (
    <Card className="border-border shadow-medium">
      <CardHeader>
        <div className="flex items-start justify-between gap-4">
          <div>
            <CardTitle className="flex items-center gap-2 font-display">
              <UserCog className="h-5 w-5 text-primary" />
              Staff
            </CardTitle>
            <CardDescription>Cashiers can sell, add customers and take payments. Owners can also manage products, staff and settings.</CardDescription>
          </div>
          <Button size="sm" onClick={() => setIsAddOpen(true)} className="gradient-primary text-primary-foreground shrink-0">
            <Plus className="h-4 w-4" />
            Add
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {isLoading && <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />}
        {staff.map(member => {
          const isSelf = member.id === user?.id;
          return (
            <div key={member.id} className="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-secondary/50 p-3">
              <div className="min-w-0">
                <p className="font-medium text-foreground truncate">
                  {member.name} {isSelf && <span className="text-muted-foreground">(you)</span>}
                </p>
                <p className="text-sm text-muted-foreground truncate">{member.email}</p>
              </div>
              <div className="flex items-center gap-2">
                <Badge variant={member.role === 'owner' ? 'default' : 'secondary'}>
                  {member.role === 'owner' ? 'Owner' : 'Cashier'}
                </Badge>
                {!isSelf && (
                  <>
                    <Select
                      value={member.role}
                      onValueChange={(r) => run(() => api('PATCH', `/staff/${member.id}`, { role: r }), `${member.name} is now ${r === 'owner' ? 'an owner' : 'a cashier'}`)}
                    >
                      <SelectTrigger className="h-8 w-28" aria-label={`Role for ${member.name}`}>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent className="bg-popover border-border">
                        <SelectItem value="cashier">Cashier</SelectItem>
                        <SelectItem value="owner">Owner</SelectItem>
                      </SelectContent>
                    </Select>
                    <Switch
                      checked={member.isActive}
                      disabled={busy}
                      aria-label={member.isActive ? `Disable ${member.name}` : `Enable ${member.name}`}
                      onCheckedChange={(active) =>
                        run(
                          () => api('PATCH', `/staff/${member.id}`, { isActive: active }),
                          active ? `${member.name} can sign in again` : `${member.name} has been signed out and disabled`,
                        )
                      }
                    />
                    <Button size="icon" variant="ghost" aria-label={`Reset password for ${member.name}`} onClick={() => { setPassword(''); setResetFor(member); }}>
                      <KeyRound className="h-4 w-4" />
                    </Button>
                    <Button
                      size="icon"
                      variant="ghost"
                      className="text-destructive"
                      aria-label={`Remove ${member.name}`}
                      onClick={() => {
                        if (window.confirm(`Remove ${member.name}? They will no longer be able to sign in.`)) {
                          run(() => api('DELETE', `/staff/${member.id}`), `${member.name} removed`);
                        }
                      }}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </>
                )}
              </div>
            </div>
          );
        })}
      </CardContent>

      <Dialog open={isAddOpen} onOpenChange={setIsAddOpen}>
        <DialogContent className="bg-card border-border">
          <DialogHeader>
            <DialogTitle className="font-display">Add staff member</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 pt-4">
            <div className="space-y-2">
              <Label htmlFor="staffName">Name</Label>
              <Input id="staffName" value={name} onChange={e => setName(e.target.value)} className="h-12" maxLength={100} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="staffEmail">Email</Label>
              <Input id="staffEmail" type="email" value={email} onChange={e => setEmail(e.target.value)} className="h-12" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="staffPassword">Temporary password</Label>
              <Input id="staffPassword" type="password" autoComplete="new-password" value={password} onChange={e => setPassword(e.target.value)} className="h-12" />
              <p className="text-xs text-muted-foreground">At least 8 characters. Share it with them in person; they can change it in Settings.</p>
            </div>
            <div className="space-y-2">
              <Label>Role</Label>
              <Select value={role} onValueChange={(r) => setRole(r as Role)}>
                <SelectTrigger className="h-12">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent className="bg-popover border-border">
                  <SelectItem value="cashier">Cashier</SelectItem>
                  <SelectItem value="owner">Owner</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <Button onClick={handleAdd} disabled={busy || !name.trim() || !email.trim() || password.length < 8} className="w-full gradient-primary text-primary-foreground">
              Add staff member
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={!!resetFor} onOpenChange={(open) => !open && setResetFor(null)}>
        <DialogContent className="bg-card border-border">
          <DialogHeader>
            <DialogTitle className="font-display">Reset password for {resetFor?.name}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 pt-4">
            <div className="space-y-2">
              <Label htmlFor="resetPassword">New password</Label>
              <Input id="resetPassword" type="password" autoComplete="new-password" value={password} onChange={e => setPassword(e.target.value)} className="h-12" />
              <p className="text-xs text-muted-foreground">They will be signed out of every device.</p>
            </div>
            <Button onClick={handleReset} disabled={busy || password.length < 8} className="w-full gradient-primary text-primary-foreground">
              Reset password
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </Card>
  );
}
