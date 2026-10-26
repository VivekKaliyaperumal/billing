import { Link, useLocation } from 'react-router-dom';
import { Store, ShoppingCart, Package, BarChart3, Settings, Users, LogOut } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useSettings } from '@/context/SettingsContext';
import { useAuth } from '@/context/AuthContext';
import { ThemeToggle } from '@/components/ThemeToggle';
import { Button } from '@/components/ui/button';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';

export function Header() {
  const location = useLocation();
  const { settings } = useSettings();
  const { user, isOwner, signOut } = useAuth();

  const navItems = [
    { path: '/', label: 'Sales', icon: ShoppingCart },
    // Product management is for the owner.
    ...(isOwner ? [{ path: '/admin', label: 'Products', icon: Package }] : []),
    { path: '/history', label: 'History', icon: BarChart3 },
    { path: '/customers', label: 'Customers', icon: Users },
    { path: '/settings', label: 'Settings', icon: Settings },
  ];

  return (
    <header className="sticky top-0 z-50 w-full border-b border-border glass">
      <div className="container flex h-16 items-center justify-between">
        <Link to="/" className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl gradient-primary shadow-medium">
            <Store className="h-5 w-5 text-primary-foreground" />
          </div>
          <span className="font-display text-xl font-bold text-foreground">{settings.shopName}</span>
        </Link>

        <div className="flex items-center gap-2">
          <nav className="flex items-center gap-1">
            {navItems.map(({ path, label, icon: Icon }) => (
              <Link
                key={path}
                to={path}
                className={cn(
                  'flex items-center gap-2 rounded-xl px-3 py-2 text-sm font-medium transition-all duration-200',
                  location.pathname === path
                    ? 'gradient-primary text-primary-foreground shadow-medium'
                    : 'text-muted-foreground hover:bg-secondary hover:text-foreground'
                )}
              >
                <Icon className="h-4 w-4" />
                <span className="hidden md:inline">{label}</span>
              </Link>
            ))}
          </nav>
          <ThemeToggle />
          <Tooltip>
            <TooltipTrigger asChild>
              <Button variant="ghost" size="icon" onClick={signOut} aria-label="Sign out">
                <LogOut className="h-4 w-4" />
              </Button>
            </TooltipTrigger>
            <TooltipContent>
              Sign out {user ? `${user.name} (${isOwner ? 'Owner' : 'Cashier'})` : ''}
            </TooltipContent>
          </Tooltip>
        </div>
      </div>
    </header>
  );
}
